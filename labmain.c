#include <stdint.h>
#include <stdbool.h>

/* Course-provided */
extern void enable_interrupt(void);

/* ===== Timer (Intel Interval Timer @ 0x04000020) ===== */
#define TMR_BASE 0x04000020u
#define TMR_STATUS (*(volatile uint32_t *)(TMR_BASE + 0x00))  /* bit0=TO; write-to-clear */
#define TMR_CONTROL (*(volatile uint32_t *)(TMR_BASE + 0x04)) /* bit0 ITO, bit1 CONT, bit2 START */
#define TMR_PERIODL (*(volatile uint32_t *)(TMR_BASE + 0x08))
#define TMR_PERIODH (*(volatile uint32_t *)(TMR_BASE + 0x0C))

#define CTL_ITO (1u << 0)
#define CTL_CONT (1u << 1)
#define CTL_START (1u << 2)
#define CTL_STOP (1u << 3)

/* ===== Switches ===== */
#define SW_BASE 0x04000010u
#define SW_DATA (*(volatile uint32_t *)(SW_BASE + 0x00))
#define SW_MASK_10BIT 0x3FFu

/* ===== VGA ===== */
#define VGA_BASE 0x08000000u
#define WIDTH 320
#define HEIGHT 240

static volatile uint8_t *const VGA = (volatile uint8_t *)VGA_BASE;

/* Backbuffer: 1 byte per pixel */
static uint8_t backbuffer[WIDTH * HEIGHT];

/* ===== Game constants ===== */
#define CELL 10
#define COLS (WIDTH / CELL)  /* 32 */
#define ROWS (HEIGHT / CELL) /* 24 */

#define PADDLE_H 5
#define PADDLE_W 1
#define LEFT_X 1
#define RIGHT_X (COLS - 2)

#define WIN_SCORE 5

/* Colors (8-bit palette-ish; values just need to differ) */
#define COL_BG 0x03
#define COL_FG 0xFF
#define COL_BALL 0xE0
#define COL_SCORE 0x7F

/* ===== 7-seg displays (active-low) ===== */
#define HEX0 (*(volatile uint8_t *)0x04000050u)
#define HEX1 (*(volatile uint8_t *)0x04000060u)
#define HEX2 (*(volatile uint8_t *)0x04000070u)
#define HEX3 (*(volatile uint8_t *)0x04000080u)
#define HEX4 (*(volatile uint8_t *)0x04000090u)
#define HEX5 (*(volatile uint8_t *)0x040000A0u)

static inline void set_display_byte(int n, uint8_t v)
{
  switch (n)
  {
  case 0:
    HEX0 = v;
    break;
  case 1:
    HEX1 = v;
    break;
  case 2:
    HEX2 = v;
    break;
  case 3:
    HEX3 = v;
    break;
  case 4:
    HEX4 = v;
    break;
  case 5:
    HEX5 = v;
    break;
  default:
    break;
  }
}

/* 7-seg patterns for 0..9 (active-high), classic */
static const uint8_t DIGIT_AH[10] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66,
    0x6D, 0x7D, 0x07, 0x7F, 0x6F};

static inline uint8_t seg_active_low(uint8_t ah)
{
  /* invert segments, keep DP off (bit7 = 1) */
  return (uint8_t)((~ah & 0x7F) | 0x80);
}

static inline void show_digit(int disp, int d)
{
  if (d < 0)
    d = 0;
  if (d > 9)
    d = 9;
  set_display_byte(disp, seg_active_low(DIGIT_AH[d]));
}

static volatile bool score_dirty = true; /* uppdatera vid start */

typedef struct
{
  int x, y;
  int dx, dy;
} ball_t;

typedef struct
{
  int x, y;
  int h;
} paddle_t;

static int ball_tick = 0;

static volatile int score_left = 0;
static volatile int score_right = 0;
static volatile bool gameon = true;

static ball_t ball;
static paddle_t leftp, rightp;

/* ===== Drawing helpers (draw into backbuffer) ===== */
static inline void set_pixel(int x, int y, uint8_t c)
{
  if ((unsigned)x >= WIDTH || (unsigned)y >= HEIGHT)
    return;
  backbuffer[y * WIDTH + x] = c;
}

static void clear_backbuffer(uint8_t c)
{
  for (int i = 0; i < WIDTH * HEIGHT; i++)
    backbuffer[i] = c;
}

static void fill_cell(int cx, int cy, uint8_t c)
{
  int sx = cx * CELL;
  int sy = cy * CELL;
  for (int y = 0; y < CELL; y++)
    for (int x = 0; x < CELL; x++)
      set_pixel(sx + x, sy + y, c);
}

static void fill_cell_rect(int cx, int cy, int cw, int ch, uint8_t c)
{
  for (int yy = 0; yy < ch; yy++)
    for (int xx = 0; xx < cw; xx++)
      fill_cell(cx + xx, cy + yy, c);
}

static void flip_buffers(void)
{
  /* Copy whole frame in one go -> no flicker */
  for (int i = 0; i < WIDTH * HEIGHT; i++)
    VGA[i] = backbuffer[i];
}

/* ===== Game logic ===== */
static void reset_ball(int dir)
{
  ball.x = COLS / 2;
  ball.y = ROWS / 2;
  ball.dx = dir; /* +1 to the right, -1 to the left */
  ball.dy = (ball.dy == 0) ? 1 : ball.dy;
}

static void init_game(void)
{
  score_left = 0;
  score_right = 0;
  gameon = true;

  leftp.x = LEFT_X;
  leftp.h = PADDLE_H;
  leftp.y = (ROWS - PADDLE_H) / 2;
  rightp.x = RIGHT_X;
  rightp.h = PADDLE_H;
  rightp.y = (ROWS - PADDLE_H) / 2;

  ball.x = COLS / 2;
  ball.y = ROWS / 2;
  ball.dx = 1;
  ball.dy = 1;
}

static void clamp_paddle(paddle_t *p)
{
  if (p->y < 0)
    p->y = 0;
  if (p->y + p->h > ROWS)
    p->y = ROWS - p->h;
}

static void move_paddle(paddle_t *p, int up)
{
  if (up)
    p->y--;
  else
    p->y++;
  clamp_paddle(p);
}

static void collide_with_paddle(ball_t *b, const paddle_t *p)
{
  /* check next-to-paddle in x depending on direction */
  int nx = b->x + b->dx;
  if (nx == p->x)
  {
    if (b->y >= p->y && b->y < (p->y + p->h))
    {
      b->dx = -b->dx;

      /* tiny variation so it doesn't get "stuck" */
      if (b->y == p->y || b->y == p->y + p->h - 1)
        b->dy = -b->dy;
    }
  }
}

static void move_ball(ball_t *b)
{
  b->x += b->dx;
  b->y += b->dy;

  /* bounce top/bottom */
  if (b->y <= 0)
  {
    b->y = 0;
    b->dy = -b->dy;
  }
  if (b->y >= ROWS - 1)
  {
    b->y = ROWS - 1;
    b->dy = -b->dy;
  }

  /* score left/right */
  if (b->x <= 0)
  {
    score_right++;
    score_dirty = true;
    reset_ball(1);
  }
  else if (b->x >= COLS - 1)
  {
    score_left++;
    score_dirty = true;
    reset_ball(-1);
  }

  if (score_left >= WIN_SCORE || score_right >= WIN_SCORE)
    gameon = false;
}

static void update_scoreboard(void)
{
  /* 
     HEX5 = vänster poäng
     HEX0 = höger poäng
     HEX1..HEX4 släckta
  */
  show_digit(5, score_left);
  show_digit(0, score_right);

  set_display_byte(1, 0xFF);
  set_display_byte(2, 0xFF);
  set_display_byte(3, 0xFF);
  set_display_byte(4, 0xFF);
}

/* ===== Render ===== */
static void render(void)
{
  clear_backbuffer(COL_BG);

  /* center line (dashed) */
  for (int y = 0; y < ROWS; y += 2)
    fill_cell(COLS / 2, y, COL_FG);

  /* paddles */
  fill_cell_rect(leftp.x, leftp.y, PADDLE_W, leftp.h, COL_FG);
  fill_cell_rect(rightp.x, rightp.y, PADDLE_W, rightp.h, COL_FG);

  /* ball */
  fill_cell(ball.x, ball.y, COL_BALL);

  /* score (little blocks at top) */
  for (int i = 0; i < score_left; i++)
    fill_cell(2 + i, 0, COL_SCORE);
  for (int i = 0; i < score_right; i++)
    fill_cell(COLS - 3 - i, 0, COL_SCORE);

  /* game over overlay */
  if (!gameon)
  {
    /* big rectangle in middle */
    fill_cell_rect(10, 8, 12, 8, 0x00);
    fill_cell_rect(11, 9, 10, 6, 0xFF);
  }

  flip_buffers();
}

/* ===== Timer init (~60 FPS) =====
   30 MHz / 60 = 500,000 cycles -> write (N-1)
*/
#define PERIOD_60HZ (500000u - 1u)

static void timer_init_60hz(void)
{
  TMR_CONTROL = CTL_STOP;
  TMR_STATUS = 0u;

  TMR_PERIODL = (uint16_t)(PERIOD_60HZ & 0xFFFFu);
  TMR_PERIODH = (uint16_t)(PERIOD_60HZ >> 16);

  TMR_CONTROL = CTL_CONT | CTL_ITO;
  TMR_CONTROL = CTL_CONT | CTL_ITO | CTL_START;
}

/* ===== Interrupt handler =====
   Timer IRQ is cause 16 in this environment.
*/
void handle_interrupt(unsigned int cause)
{
  if (cause != 16u)
    return;

  if (TMR_STATUS & 1u)
  {
    TMR_STATUS = 0u; /* ACK */

    /* Input: SW9 controls left up; SW0 controls right up */
    uint32_t sw = SW_DATA & SW_MASK_10BIT;

    int left_up = (sw & (1u << 9)) != 0;
    int right_up = (sw & (1u << 0)) != 0;

    if (gameon)
    {
      move_paddle(&leftp, left_up);
      move_paddle(&rightp, right_up);

      collide_with_paddle(&ball, &leftp);
      collide_with_paddle(&ball, &rightp);

      ball_tick++;

      if (ball_tick >= 3)
      {
        move_ball(&ball);
        ball_tick = 0;
      }
    }

    if (score_dirty)
    {
      update_scoreboard();
      score_dirty = false;
    }

    render();
  }
}

void labinit(void)
{
  init_game();
  render(); /* draw first frame immediately */

  for (int i = 0; i < 6; i++)
    set_display_byte(i, 0xFF);
  update_scoreboard();
  score_dirty = false;

  timer_init_60hz(); /* start timer */
  enable_interrupt();
}

int main(void)
{
  labinit();

  while (1)
  {
    /* game runs in interrupts */
    /* restart on gameover later: add a button read here */
  }
}
