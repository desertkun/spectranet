AS = z80-unknown-coff-as
LD = z80-unknown-coff-ld
RM = rm
ASFLAGS = -I../../include
MAPFILE = $(OUT).map
LDFLAGS = -T ../modules.ld -Map $(MAPFILE) -L ../../syslib
INSTALLDIR = ../../installer
CP = cp -f

.PHONY: clean

module:	$(ASOBJS)
	$(LD) -o $(OUT) $(ASOBJS) $(LDFLAGS) $(LIBPATH) $(LIBS)
	$(CP) $(OUT) $(INSTALLDIR)

%.o : %.asm
	$(AS) $(ASFLAGS) $< -o $@

clean:
	$(RM) -f *.o *.module *.bin *.map

