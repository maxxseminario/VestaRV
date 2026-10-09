# VestaRV: image base for the myshkin_app firmware images.
# The flash image pipeline (rv32_firmware's _rcf, rcf_flash.py) assumes the binary starts at
# 0x8000. The apps populate no interrupt vector, so without this word their first byte would be
# the code at 0x8200 and the image would load 0x200 too low. Placed at 0x8000 by
# -Wl,--section-start=.app_base=0x8000 in myshkin_app; the IVT slot it occupies reads zero,
# as the boot ROM's zero fill of 0x8000-0x81FF already leaves it.
.section .app_base, "a"
.word 0
