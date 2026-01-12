TIME4PONG – IS1200 Mini Project (DTEK‑V)

Innehåll
- Källkod (C/ASM) och Makefile
- Linkerscript: dtekv-script.lds
- Bibliotek: softfloat.a

1) Bygga projektet
Gå till projektmappen och bygg:

  make clean
  make

Detta genererar bl.a.:
- main.elf
- main.bin
- main.elf.txt (disassembly)

2) Ladda och köra på DTEK‑V
Starta (eller starta om) JTAG-daemonen och kör sedan dtekv-run.

Exempel (anpassa sökvägar):

  sudo /opt/intelFPGA/23.1std/qprogrammer/bin/jtagd --user-start
  cd ~/tools/dtekv-tools
  ./dtekv-run /mnt/c/Users/<USER>/Downloads/RARSovn/time4pong/main.bin --cable "USB-Blaster [1-1]"

När den startar får du en konsol i terminalen. Avsluta med Ctrl+C.

3) Felsökning
- "Cable not available": prova att starta om jtagd och/eller koppla ur/in USB‑Blaster.
  Exempel:
    sudo killall -9 jtagd jtagd_server
    sudo /opt/intelFPGA/23.1std/qprogrammer/bin/jtagd --user-start

- Kör du i WSL2: se till att USB‑Blaster är "attached" till WSL (t.ex. via usbipd-win i Windows)
  och att den syns med lsusb.

