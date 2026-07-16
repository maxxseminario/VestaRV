# ####################################################################

#  Created by Genus(TM) Synthesis Solution 19.15-s090_1 on Sun Jul 12 23:23:45 CDT 2026

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design chip_top_quad

create_clock -name "mclk" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/mclk_out]
create_clock -name "smclk" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/smclk_out]
create_clock -name "clk_lfxt" -period 30517.578 -waveform {0.0 15258.789} [get_pins mcu0/system0/clk_lfxt_out]
create_clock -name "clk_hfxt" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/system0/clk_hfxt_out]
create_generated_clock -name "flash_clk_mem" -divide_by 1     -source [get_pins mcu0/system0/mclk_out]   [get_pins mcu0/hart0/flash_clk_mem] 
create_clock -name "clk_scl0" -period 200.0 -waveform {0.0 100.0} [get_pins mcu0/i2c0/SCL_IN]
create_clock -name "clk_scl1" -period 200.0 -waveform {0.0 100.0} [get_pins mcu0/i2c1/SCL_IN]
create_clock -name "clk_sck0" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/spi0/sck_in]
create_clock -name "clk_sck1" -period 40.0 -waveform {0.0 20.0} [get_pins mcu0/spi1/sck_in]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks smclk]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_lfxt]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_hfxt]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_scl0]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_scl1]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_sck0]
set_false_path -from [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks smclk] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_lfxt] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_hfxt] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl0] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl1] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck0] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck1] -to [list \
  [get_clocks mclk]  \
  [get_clocks flash_clk_mem] ]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_sck0]
set_false_path -to [list \
  [get_pins mcu0/rom0/PGEN]  \
  [get_pins mcu0/npuram0/PGEN] ]
group_path -weight 1.000000 -name mclk_group -from [get_clocks mclk]
group_path -weight 1.000000 -name smclk_group -from [get_clocks smclk]
group_path -weight 1.000000 -name clk_lfxt_group -from [get_clocks clk_lfxt]
group_path -weight 1.000000 -name clk_hfxt_group -from [get_clocks clk_hfxt]
group_path -weight 1.000000 -name clk_scl0_group -from [get_clocks clk_scl0]
group_path -weight 1.000000 -name clk_scl1_group -from [get_clocks clk_scl1]
group_path -weight 1.000000 -name clk_sck0_group -from [get_clocks clk_sck0]
group_path -weight 1.000000 -name clk_sck1_group -from [get_clocks clk_sck1]
group_path -weight 1.000000 -name cg_enable_group_mclk -through [list \
  [get_pins mcu0/clint0/RC_CG_HIER_INST71/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST72/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST73/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST74/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST75/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST76/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST77/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST78/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST79/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST80/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST81/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST82/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST83/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST84/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST85/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST86/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST87/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST88/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST89/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST90/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST91/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST92/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST93/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST94/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST101/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST102/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST111/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST112/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST119/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST120/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST121/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST122/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST123/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST124/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST127/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST128/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST129/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST130/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST131/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST132/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST133/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST134/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST135/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST136/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST141/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST142/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST143/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST144/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST145/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST147/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST149/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST156/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST160/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST161/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST162/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST163/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST164/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST166/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST168/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST175/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST176/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST177/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST178/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST179/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST180/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST181/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST182/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST183/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST184/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST185/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST186/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST187/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST188/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST189/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST190/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST191/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST192/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST193/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST194/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST195/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST196/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST197/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST198/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST199/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST200/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST201/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST202/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST203/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST204/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST205/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST206/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST207/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST208/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST209/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST210/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST211/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST212/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST213/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST214/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST215/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST216/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST217/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST218/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST219/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST220/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST221/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST222/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST223/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST224/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST225/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST226/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST227/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST228/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST229/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST230/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST231/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST232/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST233/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST234/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST235/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST236/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST237/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST238/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST239/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST240/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST243/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST244/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST245/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST246/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST247/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST248/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST249/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST250/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST251/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST252/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST260/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST261/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST262/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST263/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST264/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST265/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST266/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST268/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST275/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST276/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST277/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST278/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST279/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST280/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST281/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST282/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST288/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST289/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST290/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST291/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST292/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST293/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST294/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST295/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST296/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST297/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST298/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST299/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST300/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST301/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST302/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST303/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST305/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST308/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST309/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST310/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST311/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST312/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST313/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST314/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST315/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST316/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST317/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST318/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST319/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST320/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST321/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST322/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST323/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST325/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST326/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST327/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST328/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST330/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST341/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST342/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST343/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST345/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST65/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST66/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST67/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST68/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST69/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST70/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST65/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST66/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST67/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST68/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST69/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST70/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST71/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST72/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST73/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST74/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST75/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST76/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST77/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST78/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST79/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST80/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST81/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST82/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST83/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST84/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST85/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST86/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST87/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST88/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST89/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST90/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST91/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST92/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST93/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST94/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST101/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST102/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST111/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST112/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST119/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST120/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST121/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST122/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST123/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST124/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST127/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST128/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST129/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST130/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST131/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST132/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST133/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST134/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST135/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST136/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST141/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST142/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST143/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST144/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST145/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST147/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST149/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST156/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST160/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST161/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST162/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST163/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST164/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST166/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST168/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST175/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST176/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST177/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST178/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST179/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST180/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST181/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST182/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST183/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST184/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST185/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST186/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST187/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST188/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST189/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST190/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST191/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST192/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST193/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST194/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST195/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST196/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST197/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST198/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST199/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST200/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST201/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST202/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST203/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST204/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST205/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST206/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST207/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST208/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST209/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST210/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST211/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST212/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST213/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST214/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST215/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST216/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST217/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST218/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST219/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST220/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST221/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST222/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST223/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST224/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST225/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST226/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST227/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST228/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST229/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST230/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST231/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST232/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST233/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST234/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST235/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST236/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST237/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST238/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST239/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST240/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST243/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST244/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST245/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST246/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST247/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST248/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST249/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST250/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST251/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST252/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST260/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST261/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST262/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST263/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST264/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST265/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST266/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST268/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST275/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST276/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST277/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST278/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST279/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST280/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST281/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST282/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST288/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST289/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST290/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST291/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST292/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST293/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST294/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST295/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST296/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST297/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST298/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST299/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST300/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST301/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST302/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST303/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST305/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST308/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST309/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST310/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST311/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST312/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST313/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST314/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST315/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST316/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST317/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST318/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST319/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST320/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST321/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST322/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST323/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST325/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST326/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST327/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST328/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST330/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST341/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST342/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST343/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST345/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST65/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST66/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST67/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST68/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST69/enable]  \
  [get_pins mcu0/RC_CG_HIER_INST70/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST71/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST72/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST73/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST74/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST75/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST76/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST77/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST78/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST79/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST80/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST81/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST82/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST83/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST84/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST85/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST86/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST87/enable]  \
  [get_pins mcu0/clint0/RC_CG_HIER_INST88/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST89/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST90/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST91/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST92/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST93/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST94/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins mcu0/gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST101/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST102/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST111/enable]  \
  [get_pins mcu0/gpio1/RC_CG_HIER_INST112/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST119/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST120/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST121/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST122/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST123/enable]  \
  [get_pins mcu0/gpio2/RC_CG_HIER_INST124/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST127/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST128/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST129/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST130/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST131/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST132/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST133/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST134/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST135/enable]  \
  [get_pins mcu0/gpio3/RC_CG_HIER_INST136/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST141/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST142/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST143/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST144/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST145/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST147/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST149/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST156/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST160/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST161/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST162/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST163/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST164/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST166/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST168/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST175/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST176/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST177/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST178/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST179/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST180/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST181/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST182/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST183/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST184/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST185/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST186/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST187/enable]  \
  [get_pins mcu0/irtr0/RC_CG_HIER_INST188/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST189/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST190/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST191/enable]  \
  [get_pins mcu0/mp_arb0/RC_CG_HIER_INST192/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST193/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST194/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST195/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST196/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST197/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST198/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST199/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST200/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST201/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST202/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST203/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST204/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST205/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST206/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST207/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST208/enable]  \
  [get_pins mcu0/mtx0/RC_CG_HIER_INST209/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST210/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST211/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST212/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST213/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST214/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST215/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST216/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST217/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST218/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST219/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST220/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST221/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST222/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST223/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST224/enable]  \
  [get_pins mcu0/npu0/RC_CG_HIER_INST225/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST226/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST227/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST228/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST229/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST230/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST231/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST232/enable]  \
  [get_pins mcu0/pwr0/RC_CG_HIER_INST233/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST234/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST235/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST236/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST237/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST238/enable]  \
  [get_pins mcu0/resv0/RC_CG_HIER_INST239/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST240/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST243/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST244/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST245/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST246/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST247/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST248/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST249/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST250/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST251/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST252/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST260/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST261/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST262/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST263/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST264/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST265/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST266/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST268/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST275/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST276/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST277/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST278/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST279/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST280/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST281/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST282/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST288/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST289/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST290/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST291/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST292/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST293/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST294/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST295/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST296/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST297/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST298/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST299/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST300/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST301/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST302/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST303/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST305/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST308/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST309/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST310/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST311/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST312/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST313/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST314/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST315/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST316/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST317/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST318/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST319/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST320/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST321/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST322/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST323/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST325/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST326/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST327/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST328/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST330/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST341/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST342/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST343/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST345/enable] ]
group_path -weight 1.000000 -name cg_enable_group_smclk -through [list \
  [get_pins mcu0/i2c0/CGMaster/RC_CG_HIER_INST155/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST146/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST150/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST151/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST152/enable]  \
  [get_pins mcu0/i2c1/CGMaster/RC_CG_HIER_INST174/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST157/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST158/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST165/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST169/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST170/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST171/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST241/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST242/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST253/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST254/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST255/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST256/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST257/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST258/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST267/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST269/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST270/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST271/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST272/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST273/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST329/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST331/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST332/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST333/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST334/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST335/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST336/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST337/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST338/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST339/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST340/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST344/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST346/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST347/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST348/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST349/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST350/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST351/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST352/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST353/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST354/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST355/enable]  \
  [get_pins mcu0/i2c0/CGMaster/RC_CG_HIER_INST155/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST146/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST150/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST151/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST152/enable]  \
  [get_pins mcu0/i2c1/CGMaster/RC_CG_HIER_INST174/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST157/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST158/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST165/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST169/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST170/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST171/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST241/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST242/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST253/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST254/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST255/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST256/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST257/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST258/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST267/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST269/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST270/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST271/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST272/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST273/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST329/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST331/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST332/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST333/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST334/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST335/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST336/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST337/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST338/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST339/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST340/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST344/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST346/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST347/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST348/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST349/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST350/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST351/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST352/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST353/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST354/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST355/enable]  \
  [get_pins mcu0/i2c0/CGMaster/RC_CG_HIER_INST155/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST146/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST150/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST151/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST152/enable]  \
  [get_pins mcu0/i2c1/CGMaster/RC_CG_HIER_INST174/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST157/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST158/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST165/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST169/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST170/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST171/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST241/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST242/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST253/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST254/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST255/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST256/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST257/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST258/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST267/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST269/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST270/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST271/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST272/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST273/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST329/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST331/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST332/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST333/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST334/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST335/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST336/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST337/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST338/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST339/enable]  \
  [get_pins mcu0/uart0/RC_CG_HIER_INST340/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST344/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST346/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST347/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST348/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST349/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST350/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST351/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST352/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST353/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST354/enable]  \
  [get_pins mcu0/uart1/RC_CG_HIER_INST355/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_scl0 -through [list \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST140/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST148/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST153/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST154/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST140/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST148/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST153/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST154/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST140/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST148/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST153/enable]  \
  [get_pins mcu0/i2c0/RC_CG_HIER_INST154/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_scl1 -through [list \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST159/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST167/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST172/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST173/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST159/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST167/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST172/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST173/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST159/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST167/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST172/enable]  \
  [get_pins mcu0/i2c1/RC_CG_HIER_INST173/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_sck0 -through [list \
  [get_pins mcu0/spi0/RC_CG_HIER_INST259/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST259/enable]  \
  [get_pins mcu0/spi0/RC_CG_HIER_INST259/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_sck1 -through [list \
  [get_pins mcu0/spi1/RC_CG_HIER_INST274/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST274/enable]  \
  [get_pins mcu0/spi1/RC_CG_HIER_INST274/enable] ]
group_path -weight 1.000000 -name cg_enable_group_default -through [list \
  [get_pins mcu0/system0/RC_CG_HIER_INST283/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST284/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST285/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST286/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST287/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST306/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST307/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST283/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST284/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST285/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST286/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST287/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST306/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST307/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST283/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST284/enable]  \
  [get_pins mcu0/system0/RC_CG_HIER_INST285/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST286/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST287/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST306/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST307/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_hfxt -through [list \
  [get_pins mcu0/timer0/RC_CG_HIER_INST304/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST324/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST304/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST324/enable]  \
  [get_pins mcu0/timer0/RC_CG_HIER_INST304/enable]  \
  [get_pins mcu0/timer1/RC_CG_HIER_INST324/enable] ]
set_clock_gating_check -setup 0.0 
set_max_transition 0.5 [current_design]
set_wire_load_mode "enclosed"
set_dont_touch [get_cells {mcu0/hart0 mcu0/hart1 mcu0/hart2 mcu0/hart3}]
set_dont_touch [get_nets {mcu0/npu0/Decision[15]}]
set_dont_use false [get_lib_cells */TIEHIX1MA10TH]
set_dont_use false [get_lib_cells */TIELOX1MA10TH]

# --- C0 chip-top additions (not from genus) ---------------------------------
# Keep the dangling tb-visibility a0 buses + their iso-clamp drivers alive:
# the mcu0 instance leaves a0/a0_1/a0_2/a0_3 OPEN (Myshkin vesta_chip
# precedent) and optDesign would otherwise trim the unloaded driver cone. The
# gate tb probes these nets (primary probe path: the tiles' own ports
# mcu0/hart<h>/a0, which are trim-proof; this keeps the MCU-level clamped
# nets too).
set_dont_touch [get_nets -quiet {mcu0/a0[*]}]
set_dont_touch [get_nets -quiet {mcu0/a0_*}]

# --- CQ4 hardened-tile-boundary cleanup + unregistered-pin budget -------------
# (see ~/vesta_docs/castalia_quad/cq4_timing_budgets.md for the full derivation)
#
# This SDC was a sed of the C0 chip SDC (in/chip_top.sdc), which in turn is the
# genus-emitted MCU_MP SDC transformed to the chip. Ten TCLCMD-917 fired on
# objects that exist only INSIDE the pre-hardening tile (they are now absorbed
# into the per-corner ETM out/hart_tile.etm_{ss,ff}.lib). CQ4 dispositions:
#   * hart{0..3}/ram0/PGEN  : DROPPED from the PGEN set_false_path -to list --
#       ram0 is inside the tile ETM; the tile SDC already false-paths ram0/PGEN
#       (baked into the ETM as an absent arc). rom0/npuram0 PGEN kept (real
#       top-level macros, PGEN pins present).
#   * cg_enable_group_mclk  : the hart<h> internal CG-enable pins DROPPED (they
#       resolved to empty and were silently ignored -- not 917-firing -- but are
#       stale: the tiles' clock gating is frozen in the ETM and is not re-opt'd
#       at the chip level). MCU-level peripheral CG enables retained.
#   * get_designs hart_tile : RE-TARGETED to the four hardened tile INSTANCES
#       (get_cells mcu0/hart0..3) -- the boundary-real "do not touch the tiles".
#   * TIE lib-cell qualifier : stale genus lib name scadv10_..._tt_1p0v_25c
#       replaced with a wildcard */ (the cells exist under the assembly's own
#       lib name; proven get_lib_cells */TIEHIX1MA10TH -> 1 cell).
#
# GENERATED-CLOCK (M9c) CHECK -- carried for all four tiles: clk_cpu is a
# generated clock created INSIDE the tile SDC (create_generated_clock clk_cpu
# -source clk -divide_by 1 core/clk_cpu) and is baked into the ETM, so the
# assembly builds mcu0/hart{0..3}/clk_cpu automatically (verified: check_timing
# reports "Using master clock 'mclk' for generated clock mcu0/hart{0..3}/clk_cpu").
# flash_clk_mem is likewise an ETM generated clock on all four harts; SDC line 19
# additionally (re)asserts the chip-level "flash_clk_mem" on hart0's pin (only
# hart0 wires the boot flash) -- a benign re-assertion of the ETM's hart0 clock,
# kept to stay byte-aligned with C0.
#
# UNREGISTERED-PIN BUDGET (M14 list: hart0 flash quartet, sleep, straps).
#   * sleep / hart_id / pd_iso_en / tcm_* / resetn / a0 / trap_flag are
#     set_false_path'd IN THE TILE SDC -> those arcs are ABSENT from the ETM ->
#     they carry no chip-level timing (async / static config). Nothing to budget.
#   * flash quartet (flash_dout in; flash_mab, flash_mem_en out; flash_clk_mem
#     generated clock) is UNREGISTERED at the tile boundary but at the CHIP level
#     is an ordinary single-cycle mclk (40 ns) reg-to-reg path spanning the ETM
#     boundary between hart0's core flop and mcu0/spi0 (flash_mab->spi0/mab,
#     flash_mem_en->spi0/en_mem_flash, spi0/rdata_flash->flash_dout; harts 1-3
#     leave the flash port UNCONNECTED). clk_cpu / flash_clk_mem are both DIV1 of
#     mclk = one synchronous domain, so this path is checked at 40 ns.
#     Budget (ETM ss arcs + CQ geometry): flash_mab clk->pin <=1.4 ns; hart0
#     flash pins are on the tile's center-band-facing BOTTOM edge (global y=1639,
#     x~=476), and spi0 lands in the center band directly below -> worst-case
#     Manhattan route <=1.6 mm (~<=2 ns); spi0 input->flop a few ns; total <~6 ns
#     of the 40 ns period => >34 ns (>85%) margin. flash_dout setup at the tile
#     is small/relaxed (~ -0.4 ns) so the spi0->hart0 direction has ~the full
#     cycle. A chip-level set_max_delay of 10 ns (the TILE's standalone external
#     io reserve) would OVER-constrain this 40 ns-governed path, so -- exactly as
#     C0 does -- NO chip-level set_max_delay/set_input_delay/set_output_delay is
#     added here; the 40 ns mclk reg-to-reg check across the ETM boundary governs
#     and holds with >85% margin. Re-verify at CQ5 STA once spi0 is placed.
