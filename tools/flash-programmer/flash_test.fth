\ ============================================================
\ AT45DB021E Flash Test via SPI0
\ Test: Write 0xDEADBEEF to page 0, then read back
\ ============================================================

\ ============================================================
\ Initialize SPI0 for AT45DB021E Flash
\ ============================================================
\ Configure SPI0: Master mode, CPOL=0, CPHA=0, MSB first, 8-bit
$404C0 $4200 !

\ 
\ Read Manufacturer and Device ID
\ ----------------------------------------
\ Send byte 0x9F
$9F $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read Manufacturer ID
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Print MFG ID (should be 0x1F for Atmel)
\ Read Device ID bytes
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Device ID 1
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Device ID 2
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Extended info

\ 
\ Read Flash Status Register
\ ----------------------------------------
\ Send byte 0xD7
$D7 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
\ Status byte is now on stack
\ Bit 7 = Ready, Bit 0 = Page size (0=264, 1=256)
.

\ 
\ Write 4 bytes to Buffer 1
\ ----------------------------------------
\ Send byte 0x84
$84 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Address bytes (offset 0)
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Data bytes:
\   Byte 0: 0xEF
\ Send byte 0xEF
$EF $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\   Byte 1: 0xBE
\ Send byte 0xBE
$BE $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\   Byte 2: 0xAD
\ Send byte 0xAD
$AD $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\   Byte 3: 0xDE
\ Send byte 0xDE
$DE $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL

\ 
\ Program Buffer 1 to Page 0 (with erase)
\ ----------------------------------------
\ Send byte 0x83
$83 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Page address: 0
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Wait for program to complete (check status)

\ Poll status until ready
BEGIN
\ 
\ Read Flash Status Register
\ ----------------------------------------
\ Send byte 0xD7
$D7 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
\ Status byte is now on stack
\ Bit 7 = Ready, Bit 0 = Page size (0=264, 1=256)
.

  $80 AND 0<>
UNTIL

\ 
\ Read 4 bytes from Page 0, offset 0
\ ----------------------------------------
\ Send byte 0xD2
$D2 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Page address: 0, offset: 0
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ 4 don't care bytes
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read 4 data bytes:
\   Byte 0:
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Print byte
\   Byte 1:
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Print byte
\   Byte 2:
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Print byte
\   Byte 3:
\ Send byte 0x00
$0 $4208 !
\ Wait for SPI ready (BUSY=0)
BEGIN
  $4204 @
  4 AND 0=
UNTIL
\ Read received byte
$420C @
. \ Print byte

\ ============================================================
\ Test complete - check if read values match 0xEF 0xBE 0xAD 0xDE
\ ============================================================
