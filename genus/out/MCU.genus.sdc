# ####################################################################

#  Created by Genus(TM) Synthesis Solution 19.15-s090_1 on Thu Nov 13 19:43:51 CST 2025

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1000fF
set_units -time 1000ps

# Set the current design
current_design MCU

create_clock -name "mclk" -period 28.57143 -waveform {0.0 14.285715} [get_pins system0/mclk_out]
create_clock -name "smclk" -period 28.57143 -waveform {0.0 14.285715} [get_pins system0/smclk_out]
create_clock -name "clk_cpu" -period 28.57143 -waveform {0.0 14.285715} [get_pins core/clk_cpu]
create_clock -name "clk_lfxt" -period 30517.578 -waveform {0.0 15258.789} [get_pins system0/clk_lfxt_out]
create_clock -name "clk_hfxt" -period 28.57143 -waveform {0.0 14.285715} [get_pins system0/clk_hfxt_out]
create_clock -name "clk_scl0" -period 200.0 -waveform {0.0 100.0} [get_pins i2c0/SCL_IN]
create_clock -name "clk_scl1" -period 200.0 -waveform {0.0 100.0} [get_pins i2c1/SCL_IN]
create_clock -name "clk_sck0" -period 28.57143 -waveform {0.0 14.285715} [get_pins spi0/sck_in]
create_clock -name "clk_sck1" -period 28.57143 -waveform {0.0 14.285715} [get_pins spi1/sck_in]
set_false_path -from [get_clocks mclk] -to [get_clocks smclk]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks mclk] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks smclk] -to [get_clocks mclk]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks smclk] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_cpu] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_lfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_hfxt] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck0]
set_false_path -from [get_clocks clk_scl1] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck0] -to [get_clocks clk_sck1]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks mclk]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks smclk]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_cpu]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_lfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_hfxt]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl0]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_scl1]
set_false_path -from [get_clocks clk_sck1] -to [get_clocks clk_sck0]
set_load -pin_load 0.6 [get_ports resetn_out]
set_load -pin_load 0.6 [get_ports resetn_dir]
set_load -pin_load 0.6 [get_ports resetn_ren]
set_load -pin_load 0.6 [get_ports {prt1_out[7]}]
set_load -pin_load 0.6 [get_ports {prt1_out[6]}]
set_load -pin_load 0.6 [get_ports {prt1_out[5]}]
set_load -pin_load 0.6 [get_ports {prt1_out[4]}]
set_load -pin_load 0.6 [get_ports {prt1_out[3]}]
set_load -pin_load 0.6 [get_ports {prt1_out[2]}]
set_load -pin_load 0.6 [get_ports {prt1_out[1]}]
set_load -pin_load 0.6 [get_ports {prt1_out[0]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[7]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[6]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[5]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[4]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[3]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[2]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[1]}]
set_load -pin_load 0.6 [get_ports {prt1_dir[0]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[7]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[6]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[5]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[4]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[3]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[2]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[1]}]
set_load -pin_load 0.6 [get_ports {prt1_ren[0]}]
set_load -pin_load 0.6 [get_ports {prt2_out[7]}]
set_load -pin_load 0.6 [get_ports {prt2_out[6]}]
set_load -pin_load 0.6 [get_ports {prt2_out[5]}]
set_load -pin_load 0.6 [get_ports {prt2_out[4]}]
set_load -pin_load 0.6 [get_ports {prt2_out[3]}]
set_load -pin_load 0.6 [get_ports {prt2_out[2]}]
set_load -pin_load 0.6 [get_ports {prt2_out[1]}]
set_load -pin_load 0.6 [get_ports {prt2_out[0]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[7]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[6]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[5]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[4]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[3]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[2]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[1]}]
set_load -pin_load 0.6 [get_ports {prt2_dir[0]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[7]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[6]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[5]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[4]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[3]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[2]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[1]}]
set_load -pin_load 0.6 [get_ports {prt2_ren[0]}]
set_load -pin_load 0.6 [get_ports {prt3_out[7]}]
set_load -pin_load 0.6 [get_ports {prt3_out[6]}]
set_load -pin_load 0.6 [get_ports {prt3_out[5]}]
set_load -pin_load 0.6 [get_ports {prt3_out[4]}]
set_load -pin_load 0.6 [get_ports {prt3_out[3]}]
set_load -pin_load 0.6 [get_ports {prt3_out[2]}]
set_load -pin_load 0.6 [get_ports {prt3_out[1]}]
set_load -pin_load 0.6 [get_ports {prt3_out[0]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[7]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[6]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[5]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[4]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[3]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[2]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[1]}]
set_load -pin_load 0.6 [get_ports {prt3_dir[0]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[7]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[6]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[5]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[4]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[3]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[2]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[1]}]
set_load -pin_load 0.6 [get_ports {prt3_ren[0]}]
set_load -pin_load 0.6 [get_ports {prt4_out[7]}]
set_load -pin_load 0.6 [get_ports {prt4_out[6]}]
set_load -pin_load 0.6 [get_ports {prt4_out[5]}]
set_load -pin_load 0.6 [get_ports {prt4_out[4]}]
set_load -pin_load 0.6 [get_ports {prt4_out[3]}]
set_load -pin_load 0.6 [get_ports {prt4_out[2]}]
set_load -pin_load 0.6 [get_ports {prt4_out[1]}]
set_load -pin_load 0.6 [get_ports {prt4_out[0]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[7]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[6]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[5]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[4]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[3]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[2]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[1]}]
set_load -pin_load 0.6 [get_ports {prt4_dir[0]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[7]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[6]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[5]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[4]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[3]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[2]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[1]}]
set_load -pin_load 0.6 [get_ports {prt4_ren[0]}]
set_load -pin_load 0.6 [get_ports use_dac_glb_bias]
set_load -pin_load 0.6 [get_ports en_bias_buf]
set_load -pin_load 0.6 [get_ports en_bias_gen]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_ADJ[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBP[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBN[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBPC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_DBNC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_POT[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_POT[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[16]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[15]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[14]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_TIA_G_POT[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_REV_POT[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_TC_DSADC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_LC_DSADC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_RIN_DSADC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_RFB_DSADC[0]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[13]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[12]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[11]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[10]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[9]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[8]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[7]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[6]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[5]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[4]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[3]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[2]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[1]}]
set_load -pin_load 0.6 [get_ports {BIAS_DSADC_VCM[0]}]
set_load -pin_load 0.6 [get_ports dsadc_en]
set_load -pin_load 0.6 [get_ports dsadc_clk]
set_load -pin_load 0.6 [get_ports {dsadc_switch[2]}]
set_load -pin_load 0.6 [get_ports {dsadc_switch[1]}]
set_load -pin_load 0.6 [get_ports {dsadc_switch[0]}]
set_load -pin_load 0.6 [get_ports dac_en_pot]
set_load -pin_load 0.6 [get_ports adc_ext_in]
set_load -pin_load 0.6 [get_ports atp_en]
set_load -pin_load 0.6 [get_ports atp_sel]
set_load -pin_load 0.6 [get_ports adc_sel]
set_load -pin_load 0.6 [get_ports saradc_clk]
set_load -pin_load 0.6 [get_ports saradc_rst]
set_load -pin_load 0.6 [get_ports {a0[31]}]
set_load -pin_load 0.6 [get_ports {a0[30]}]
set_load -pin_load 0.6 [get_ports {a0[29]}]
set_load -pin_load 0.6 [get_ports {a0[28]}]
set_load -pin_load 0.6 [get_ports {a0[27]}]
set_load -pin_load 0.6 [get_ports {a0[26]}]
set_load -pin_load 0.6 [get_ports {a0[25]}]
set_load -pin_load 0.6 [get_ports {a0[24]}]
set_load -pin_load 0.6 [get_ports {a0[23]}]
set_load -pin_load 0.6 [get_ports {a0[22]}]
set_load -pin_load 0.6 [get_ports {a0[21]}]
set_load -pin_load 0.6 [get_ports {a0[20]}]
set_load -pin_load 0.6 [get_ports {a0[19]}]
set_load -pin_load 0.6 [get_ports {a0[18]}]
set_load -pin_load 0.6 [get_ports {a0[17]}]
set_load -pin_load 0.6 [get_ports {a0[16]}]
set_load -pin_load 0.6 [get_ports {a0[15]}]
set_load -pin_load 0.6 [get_ports {a0[14]}]
set_load -pin_load 0.6 [get_ports {a0[13]}]
set_load -pin_load 0.6 [get_ports {a0[12]}]
set_load -pin_load 0.6 [get_ports {a0[11]}]
set_load -pin_load 0.6 [get_ports {a0[10]}]
set_load -pin_load 0.6 [get_ports {a0[9]}]
set_load -pin_load 0.6 [get_ports {a0[8]}]
set_load -pin_load 0.6 [get_ports {a0[7]}]
set_load -pin_load 0.6 [get_ports {a0[6]}]
set_load -pin_load 0.6 [get_ports {a0[5]}]
set_load -pin_load 0.6 [get_ports {a0[4]}]
set_load -pin_load 0.6 [get_ports {a0[3]}]
set_load -pin_load 0.6 [get_ports {a0[2]}]
set_load -pin_load 0.6 [get_ports {a0[1]}]
set_load -pin_load 0.6 [get_ports {a0[0]}]
set_false_path -to [list \
  [get_pins rom0/PGEN]  \
  [get_pins ram0/PGEN]  \
  [get_pins ram1/PGEN] ]
group_path -weight 1.000000 -name mclk_group -from [get_clocks mclk]
group_path -weight 1.000000 -name smclk_group -from [get_clocks smclk]
group_path -weight 1.000000 -name clk_cpu_group -from [get_clocks clk_cpu]
group_path -weight 1.000000 -name clk_lfxt_group -from [get_clocks clk_lfxt]
group_path -weight 1.000000 -name clk_hfxt_group -from [get_clocks clk_hfxt]
group_path -weight 1.000000 -name clk_scl0_group -from [get_clocks clk_scl0]
group_path -weight 1.000000 -name clk_scl1_group -from [get_clocks clk_scl1]
group_path -weight 1.000000 -name clk_sck0_group -from [get_clocks clk_sck0]
group_path -weight 1.000000 -name clk_sck1_group -from [get_clocks clk_sck1]
group_path -weight 1.000000 -name cg_enable_group_clk_cpu -through [list \
  [get_pins adddec0/RC_CG_HIER_INST0/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST1/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST2/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST3/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST4/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST5/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST6/enable]  \
  [get_pins afe0/RC_CG_HIER_INST7/enable]  \
  [get_pins afe0/RC_CG_HIER_INST8/enable]  \
  [get_pins afe0/RC_CG_HIER_INST9/enable]  \
  [get_pins afe0/RC_CG_HIER_INST10/enable]  \
  [get_pins afe0/RC_CG_HIER_INST11/enable]  \
  [get_pins afe0/RC_CG_HIER_INST12/enable]  \
  [get_pins afe0/RC_CG_HIER_INST13/enable]  \
  [get_pins afe0/RC_CG_HIER_INST14/enable]  \
  [get_pins afe0/RC_CG_HIER_INST15/enable]  \
  [get_pins afe0/RC_CG_HIER_INST16/enable]  \
  [get_pins afe0/RC_CG_HIER_INST17/enable]  \
  [get_pins afe0/RC_CG_HIER_INST18/enable]  \
  [get_pins afe0/RC_CG_HIER_INST19/enable]  \
  [get_pins afe0/RC_CG_HIER_INST20/enable]  \
  [get_pins afe0/RC_CG_HIER_INST21/enable]  \
  [get_pins afe0/RC_CG_HIER_INST22/enable]  \
  [get_pins afe0/RC_CG_HIER_INST23/enable]  \
  [get_pins afe0/RC_CG_HIER_INST24/enable]  \
  [get_pins afe0/RC_CG_HIER_INST25/enable]  \
  [get_pins afe0/RC_CG_HIER_INST26/enable]  \
  [get_pins afe0/RC_CG_HIER_INST27/enable]  \
  [get_pins afe0/RC_CG_HIER_INST28/enable]  \
  [get_pins afe0/RC_CG_HIER_INST29/enable]  \
  [get_pins afe0/RC_CG_HIER_INST30/enable]  \
  [get_pins afe0/RC_CG_HIER_INST31/enable]  \
  [get_pins afe0/RC_CG_HIER_INST32/enable]  \
  [get_pins afe0/RC_CG_HIER_INST33/enable]  \
  [get_pins afe0/RC_CG_HIER_INST34/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST101/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST102/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST111/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST112/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST119/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST120/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST121/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST122/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST123/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST124/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST128/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST129/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST130/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST131/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST132/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST133/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST135/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST136/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST142/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST143/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST144/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST145/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST146/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST147/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST149/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST150/enable]  \
  [get_pins npu0/RC_CG_HIER_INST162/enable]  \
  [get_pins npu0/RC_CG_HIER_INST163/enable]  \
  [get_pins npu0/RC_CG_HIER_INST164/enable]  \
  [get_pins npu0/RC_CG_HIER_INST165/enable]  \
  [get_pins npu0/RC_CG_HIER_INST166/enable]  \
  [get_pins npu0/RC_CG_HIER_INST167/enable]  \
  [get_pins npu0/RC_CG_HIER_INST168/enable]  \
  [get_pins npu0/RC_CG_HIER_INST169/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST173/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST174/enable]  \
  [get_pins spi0/RC_CG_HIER_INST178/enable]  \
  [get_pins spi0/RC_CG_HIER_INST179/enable]  \
  [get_pins spi0/RC_CG_HIER_INST180/enable]  \
  [get_pins spi0/RC_CG_HIER_INST181/enable]  \
  [get_pins spi0/RC_CG_HIER_INST182/enable]  \
  [get_pins spi0/RC_CG_HIER_INST183/enable]  \
  [get_pins spi0/RC_CG_HIER_INST184/enable]  \
  [get_pins spi0/RC_CG_HIER_INST185/enable]  \
  [get_pins spi0/RC_CG_HIER_INST186/enable]  \
  [get_pins spi0/RC_CG_HIER_INST187/enable]  \
  [get_pins spi0/RC_CG_HIER_INST189/enable]  \
  [get_pins spi1/RC_CG_HIER_INST196/enable]  \
  [get_pins spi1/RC_CG_HIER_INST197/enable]  \
  [get_pins spi1/RC_CG_HIER_INST198/enable]  \
  [get_pins spi1/RC_CG_HIER_INST199/enable]  \
  [get_pins spi1/RC_CG_HIER_INST200/enable]  \
  [get_pins spi1/RC_CG_HIER_INST201/enable]  \
  [get_pins spi1/RC_CG_HIER_INST202/enable]  \
  [get_pins spi1/RC_CG_HIER_INST204/enable]  \
  [get_pins system0/RC_CG_HIER_INST211/enable]  \
  [get_pins system0/RC_CG_HIER_INST212/enable]  \
  [get_pins system0/RC_CG_HIER_INST213/enable]  \
  [get_pins system0/RC_CG_HIER_INST214/enable]  \
  [get_pins system0/RC_CG_HIER_INST215/enable]  \
  [get_pins system0/RC_CG_HIER_INST216/enable]  \
  [get_pins system0/RC_CG_HIER_INST217/enable]  \
  [get_pins system0/RC_CG_HIER_INST218/enable]  \
  [get_pins system0/RC_CG_HIER_INST219/enable]  \
  [get_pins system0/RC_CG_HIER_INST220/enable]  \
  [get_pins system0/RC_CG_HIER_INST221/enable]  \
  [get_pins system0/RC_CG_HIER_INST222/enable]  \
  [get_pins system0/RC_CG_HIER_INST223/enable]  \
  [get_pins system0/RC_CG_HIER_INST224/enable]  \
  [get_pins system0/RC_CG_HIER_INST225/enable]  \
  [get_pins system0/RC_CG_HIER_INST226/enable]  \
  [get_pins system0/RC_CG_HIER_INST227/enable]  \
  [get_pins system0/RC_CG_HIER_INST228/enable]  \
  [get_pins system0/RC_CG_HIER_INST229/enable]  \
  [get_pins system0/RC_CG_HIER_INST230/enable]  \
  [get_pins system0/RC_CG_HIER_INST231/enable]  \
  [get_pins system0/RC_CG_HIER_INST232/enable]  \
  [get_pins system0/RC_CG_HIER_INST233/enable]  \
  [get_pins system0/RC_CG_HIER_INST234/enable]  \
  [get_pins system0/RC_CG_HIER_INST235/enable]  \
  [get_pins system0/RC_CG_HIER_INST236/enable]  \
  [get_pins system0/RC_CG_HIER_INST237/enable]  \
  [get_pins system0/RC_CG_HIER_INST238/enable]  \
  [get_pins system0/RC_CG_HIER_INST239/enable]  \
  [get_pins system0/RC_CG_HIER_INST240/enable]  \
  [get_pins timer0/RC_CG_HIER_INST246/enable]  \
  [get_pins timer0/RC_CG_HIER_INST247/enable]  \
  [get_pins timer0/RC_CG_HIER_INST248/enable]  \
  [get_pins timer0/RC_CG_HIER_INST249/enable]  \
  [get_pins timer0/RC_CG_HIER_INST250/enable]  \
  [get_pins timer0/RC_CG_HIER_INST251/enable]  \
  [get_pins timer0/RC_CG_HIER_INST252/enable]  \
  [get_pins timer0/RC_CG_HIER_INST253/enable]  \
  [get_pins timer0/RC_CG_HIER_INST254/enable]  \
  [get_pins timer0/RC_CG_HIER_INST255/enable]  \
  [get_pins timer0/RC_CG_HIER_INST256/enable]  \
  [get_pins timer0/RC_CG_HIER_INST257/enable]  \
  [get_pins timer0/RC_CG_HIER_INST258/enable]  \
  [get_pins timer0/RC_CG_HIER_INST259/enable]  \
  [get_pins timer0/RC_CG_HIER_INST260/enable]  \
  [get_pins timer0/RC_CG_HIER_INST261/enable]  \
  [get_pins timer0/RC_CG_HIER_INST263/enable]  \
  [get_pins timer1/RC_CG_HIER_INST266/enable]  \
  [get_pins timer1/RC_CG_HIER_INST267/enable]  \
  [get_pins timer1/RC_CG_HIER_INST268/enable]  \
  [get_pins timer1/RC_CG_HIER_INST269/enable]  \
  [get_pins timer1/RC_CG_HIER_INST270/enable]  \
  [get_pins timer1/RC_CG_HIER_INST271/enable]  \
  [get_pins timer1/RC_CG_HIER_INST272/enable]  \
  [get_pins timer1/RC_CG_HIER_INST273/enable]  \
  [get_pins timer1/RC_CG_HIER_INST274/enable]  \
  [get_pins timer1/RC_CG_HIER_INST275/enable]  \
  [get_pins timer1/RC_CG_HIER_INST276/enable]  \
  [get_pins timer1/RC_CG_HIER_INST277/enable]  \
  [get_pins timer1/RC_CG_HIER_INST278/enable]  \
  [get_pins timer1/RC_CG_HIER_INST279/enable]  \
  [get_pins timer1/RC_CG_HIER_INST280/enable]  \
  [get_pins timer1/RC_CG_HIER_INST281/enable]  \
  [get_pins timer1/RC_CG_HIER_INST283/enable]  \
  [get_pins uart0/RC_CG_HIER_INST284/enable]  \
  [get_pins uart0/RC_CG_HIER_INST285/enable]  \
  [get_pins uart0/RC_CG_HIER_INST286/enable]  \
  [get_pins uart0/RC_CG_HIER_INST288/enable]  \
  [get_pins uart1/RC_CG_HIER_INST299/enable]  \
  [get_pins uart1/RC_CG_HIER_INST300/enable]  \
  [get_pins uart1/RC_CG_HIER_INST301/enable]  \
  [get_pins uart1/RC_CG_HIER_INST303/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST0/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST1/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST2/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST3/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST4/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST5/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST6/enable]  \
  [get_pins afe0/RC_CG_HIER_INST7/enable]  \
  [get_pins afe0/RC_CG_HIER_INST8/enable]  \
  [get_pins afe0/RC_CG_HIER_INST9/enable]  \
  [get_pins afe0/RC_CG_HIER_INST10/enable]  \
  [get_pins afe0/RC_CG_HIER_INST11/enable]  \
  [get_pins afe0/RC_CG_HIER_INST12/enable]  \
  [get_pins afe0/RC_CG_HIER_INST13/enable]  \
  [get_pins afe0/RC_CG_HIER_INST14/enable]  \
  [get_pins afe0/RC_CG_HIER_INST15/enable]  \
  [get_pins afe0/RC_CG_HIER_INST16/enable]  \
  [get_pins afe0/RC_CG_HIER_INST17/enable]  \
  [get_pins afe0/RC_CG_HIER_INST18/enable]  \
  [get_pins afe0/RC_CG_HIER_INST19/enable]  \
  [get_pins afe0/RC_CG_HIER_INST20/enable]  \
  [get_pins afe0/RC_CG_HIER_INST21/enable]  \
  [get_pins afe0/RC_CG_HIER_INST22/enable]  \
  [get_pins afe0/RC_CG_HIER_INST23/enable]  \
  [get_pins afe0/RC_CG_HIER_INST24/enable]  \
  [get_pins afe0/RC_CG_HIER_INST25/enable]  \
  [get_pins afe0/RC_CG_HIER_INST26/enable]  \
  [get_pins afe0/RC_CG_HIER_INST27/enable]  \
  [get_pins afe0/RC_CG_HIER_INST28/enable]  \
  [get_pins afe0/RC_CG_HIER_INST29/enable]  \
  [get_pins afe0/RC_CG_HIER_INST30/enable]  \
  [get_pins afe0/RC_CG_HIER_INST31/enable]  \
  [get_pins afe0/RC_CG_HIER_INST32/enable]  \
  [get_pins afe0/RC_CG_HIER_INST33/enable]  \
  [get_pins afe0/RC_CG_HIER_INST34/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST101/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST102/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST111/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST112/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST119/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST120/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST121/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST122/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST123/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST124/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST128/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST129/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST130/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST131/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST132/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST133/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST135/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST136/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST142/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST143/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST144/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST145/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST146/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST147/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST149/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST150/enable]  \
  [get_pins npu0/RC_CG_HIER_INST162/enable]  \
  [get_pins npu0/RC_CG_HIER_INST163/enable]  \
  [get_pins npu0/RC_CG_HIER_INST164/enable]  \
  [get_pins npu0/RC_CG_HIER_INST165/enable]  \
  [get_pins npu0/RC_CG_HIER_INST166/enable]  \
  [get_pins npu0/RC_CG_HIER_INST167/enable]  \
  [get_pins npu0/RC_CG_HIER_INST168/enable]  \
  [get_pins npu0/RC_CG_HIER_INST169/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST173/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST174/enable]  \
  [get_pins spi0/RC_CG_HIER_INST178/enable]  \
  [get_pins spi0/RC_CG_HIER_INST179/enable]  \
  [get_pins spi0/RC_CG_HIER_INST180/enable]  \
  [get_pins spi0/RC_CG_HIER_INST181/enable]  \
  [get_pins spi0/RC_CG_HIER_INST182/enable]  \
  [get_pins spi0/RC_CG_HIER_INST183/enable]  \
  [get_pins spi0/RC_CG_HIER_INST184/enable]  \
  [get_pins spi0/RC_CG_HIER_INST185/enable]  \
  [get_pins spi0/RC_CG_HIER_INST186/enable]  \
  [get_pins spi0/RC_CG_HIER_INST187/enable]  \
  [get_pins spi0/RC_CG_HIER_INST189/enable]  \
  [get_pins spi1/RC_CG_HIER_INST196/enable]  \
  [get_pins spi1/RC_CG_HIER_INST197/enable]  \
  [get_pins spi1/RC_CG_HIER_INST198/enable]  \
  [get_pins spi1/RC_CG_HIER_INST199/enable]  \
  [get_pins spi1/RC_CG_HIER_INST200/enable]  \
  [get_pins spi1/RC_CG_HIER_INST201/enable]  \
  [get_pins spi1/RC_CG_HIER_INST202/enable]  \
  [get_pins spi1/RC_CG_HIER_INST204/enable]  \
  [get_pins system0/RC_CG_HIER_INST211/enable]  \
  [get_pins system0/RC_CG_HIER_INST212/enable]  \
  [get_pins system0/RC_CG_HIER_INST213/enable]  \
  [get_pins system0/RC_CG_HIER_INST214/enable]  \
  [get_pins system0/RC_CG_HIER_INST215/enable]  \
  [get_pins system0/RC_CG_HIER_INST216/enable]  \
  [get_pins system0/RC_CG_HIER_INST217/enable]  \
  [get_pins system0/RC_CG_HIER_INST218/enable]  \
  [get_pins system0/RC_CG_HIER_INST219/enable]  \
  [get_pins system0/RC_CG_HIER_INST220/enable]  \
  [get_pins system0/RC_CG_HIER_INST221/enable]  \
  [get_pins system0/RC_CG_HIER_INST222/enable]  \
  [get_pins system0/RC_CG_HIER_INST223/enable]  \
  [get_pins system0/RC_CG_HIER_INST224/enable]  \
  [get_pins system0/RC_CG_HIER_INST225/enable]  \
  [get_pins system0/RC_CG_HIER_INST226/enable]  \
  [get_pins system0/RC_CG_HIER_INST227/enable]  \
  [get_pins system0/RC_CG_HIER_INST228/enable]  \
  [get_pins system0/RC_CG_HIER_INST229/enable]  \
  [get_pins system0/RC_CG_HIER_INST230/enable]  \
  [get_pins system0/RC_CG_HIER_INST231/enable]  \
  [get_pins system0/RC_CG_HIER_INST232/enable]  \
  [get_pins system0/RC_CG_HIER_INST233/enable]  \
  [get_pins system0/RC_CG_HIER_INST234/enable]  \
  [get_pins system0/RC_CG_HIER_INST235/enable]  \
  [get_pins system0/RC_CG_HIER_INST236/enable]  \
  [get_pins system0/RC_CG_HIER_INST237/enable]  \
  [get_pins system0/RC_CG_HIER_INST238/enable]  \
  [get_pins system0/RC_CG_HIER_INST239/enable]  \
  [get_pins system0/RC_CG_HIER_INST240/enable]  \
  [get_pins timer0/RC_CG_HIER_INST246/enable]  \
  [get_pins timer0/RC_CG_HIER_INST247/enable]  \
  [get_pins timer0/RC_CG_HIER_INST248/enable]  \
  [get_pins timer0/RC_CG_HIER_INST249/enable]  \
  [get_pins timer0/RC_CG_HIER_INST250/enable]  \
  [get_pins timer0/RC_CG_HIER_INST251/enable]  \
  [get_pins timer0/RC_CG_HIER_INST252/enable]  \
  [get_pins timer0/RC_CG_HIER_INST253/enable]  \
  [get_pins timer0/RC_CG_HIER_INST254/enable]  \
  [get_pins timer0/RC_CG_HIER_INST255/enable]  \
  [get_pins timer0/RC_CG_HIER_INST256/enable]  \
  [get_pins timer0/RC_CG_HIER_INST257/enable]  \
  [get_pins timer0/RC_CG_HIER_INST258/enable]  \
  [get_pins timer0/RC_CG_HIER_INST259/enable]  \
  [get_pins timer0/RC_CG_HIER_INST260/enable]  \
  [get_pins timer0/RC_CG_HIER_INST261/enable]  \
  [get_pins timer0/RC_CG_HIER_INST263/enable]  \
  [get_pins timer1/RC_CG_HIER_INST266/enable]  \
  [get_pins timer1/RC_CG_HIER_INST267/enable]  \
  [get_pins timer1/RC_CG_HIER_INST268/enable]  \
  [get_pins timer1/RC_CG_HIER_INST269/enable]  \
  [get_pins timer1/RC_CG_HIER_INST270/enable]  \
  [get_pins timer1/RC_CG_HIER_INST271/enable]  \
  [get_pins timer1/RC_CG_HIER_INST272/enable]  \
  [get_pins timer1/RC_CG_HIER_INST273/enable]  \
  [get_pins timer1/RC_CG_HIER_INST274/enable]  \
  [get_pins timer1/RC_CG_HIER_INST275/enable]  \
  [get_pins timer1/RC_CG_HIER_INST276/enable]  \
  [get_pins timer1/RC_CG_HIER_INST277/enable]  \
  [get_pins timer1/RC_CG_HIER_INST278/enable]  \
  [get_pins timer1/RC_CG_HIER_INST279/enable]  \
  [get_pins timer1/RC_CG_HIER_INST280/enable]  \
  [get_pins timer1/RC_CG_HIER_INST281/enable]  \
  [get_pins timer1/RC_CG_HIER_INST283/enable]  \
  [get_pins uart0/RC_CG_HIER_INST284/enable]  \
  [get_pins uart0/RC_CG_HIER_INST285/enable]  \
  [get_pins uart0/RC_CG_HIER_INST286/enable]  \
  [get_pins uart0/RC_CG_HIER_INST288/enable]  \
  [get_pins uart1/RC_CG_HIER_INST299/enable]  \
  [get_pins uart1/RC_CG_HIER_INST300/enable]  \
  [get_pins uart1/RC_CG_HIER_INST301/enable]  \
  [get_pins uart1/RC_CG_HIER_INST303/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST0/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST1/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST2/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST3/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST4/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST5/enable]  \
  [get_pins adddec0/RC_CG_HIER_INST6/enable]  \
  [get_pins afe0/RC_CG_HIER_INST7/enable]  \
  [get_pins afe0/RC_CG_HIER_INST8/enable]  \
  [get_pins afe0/RC_CG_HIER_INST9/enable]  \
  [get_pins afe0/RC_CG_HIER_INST10/enable]  \
  [get_pins afe0/RC_CG_HIER_INST11/enable]  \
  [get_pins afe0/RC_CG_HIER_INST12/enable]  \
  [get_pins afe0/RC_CG_HIER_INST13/enable]  \
  [get_pins afe0/RC_CG_HIER_INST14/enable]  \
  [get_pins afe0/RC_CG_HIER_INST15/enable]  \
  [get_pins afe0/RC_CG_HIER_INST16/enable]  \
  [get_pins afe0/RC_CG_HIER_INST17/enable]  \
  [get_pins afe0/RC_CG_HIER_INST18/enable]  \
  [get_pins afe0/RC_CG_HIER_INST19/enable]  \
  [get_pins afe0/RC_CG_HIER_INST20/enable]  \
  [get_pins afe0/RC_CG_HIER_INST21/enable]  \
  [get_pins afe0/RC_CG_HIER_INST22/enable]  \
  [get_pins afe0/RC_CG_HIER_INST23/enable]  \
  [get_pins afe0/RC_CG_HIER_INST24/enable]  \
  [get_pins afe0/RC_CG_HIER_INST25/enable]  \
  [get_pins afe0/RC_CG_HIER_INST26/enable]  \
  [get_pins afe0/RC_CG_HIER_INST27/enable]  \
  [get_pins afe0/RC_CG_HIER_INST28/enable]  \
  [get_pins afe0/RC_CG_HIER_INST29/enable]  \
  [get_pins afe0/RC_CG_HIER_INST30/enable]  \
  [get_pins afe0/RC_CG_HIER_INST31/enable]  \
  [get_pins afe0/RC_CG_HIER_INST32/enable]  \
  [get_pins afe0/RC_CG_HIER_INST33/enable]  \
  [get_pins afe0/RC_CG_HIER_INST34/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST95/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST96/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST97/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST98/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST99/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST100/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST101/enable]  \
  [get_pins gpio0/RC_CG_HIER_INST102/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST103/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST104/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST105/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST106/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST107/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST108/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST109/enable]  \
  [get_pins gpio1/RC_CG_HIER_INST110/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST111/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST112/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST113/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST114/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST115/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST116/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST117/enable]  \
  [get_pins gpio2/RC_CG_HIER_INST118/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST119/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST120/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST121/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST122/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST123/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST124/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST125/enable]  \
  [get_pins gpio3/RC_CG_HIER_INST126/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST128/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST129/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST130/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST131/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST132/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST133/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST135/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST136/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST142/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST143/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST144/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST145/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST146/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST147/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST149/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST150/enable]  \
  [get_pins npu0/RC_CG_HIER_INST162/enable]  \
  [get_pins npu0/RC_CG_HIER_INST163/enable]  \
  [get_pins npu0/RC_CG_HIER_INST164/enable]  \
  [get_pins npu0/RC_CG_HIER_INST165/enable]  \
  [get_pins npu0/RC_CG_HIER_INST166/enable]  \
  [get_pins npu0/RC_CG_HIER_INST167/enable]  \
  [get_pins npu0/RC_CG_HIER_INST168/enable]  \
  [get_pins npu0/RC_CG_HIER_INST169/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST173/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST174/enable]  \
  [get_pins spi0/RC_CG_HIER_INST178/enable]  \
  [get_pins spi0/RC_CG_HIER_INST179/enable]  \
  [get_pins spi0/RC_CG_HIER_INST180/enable]  \
  [get_pins spi0/RC_CG_HIER_INST181/enable]  \
  [get_pins spi0/RC_CG_HIER_INST182/enable]  \
  [get_pins spi0/RC_CG_HIER_INST183/enable]  \
  [get_pins spi0/RC_CG_HIER_INST184/enable]  \
  [get_pins spi0/RC_CG_HIER_INST185/enable]  \
  [get_pins spi0/RC_CG_HIER_INST186/enable]  \
  [get_pins spi0/RC_CG_HIER_INST187/enable]  \
  [get_pins spi0/RC_CG_HIER_INST189/enable]  \
  [get_pins spi1/RC_CG_HIER_INST196/enable]  \
  [get_pins spi1/RC_CG_HIER_INST197/enable]  \
  [get_pins spi1/RC_CG_HIER_INST198/enable]  \
  [get_pins spi1/RC_CG_HIER_INST199/enable]  \
  [get_pins spi1/RC_CG_HIER_INST200/enable]  \
  [get_pins spi1/RC_CG_HIER_INST201/enable]  \
  [get_pins spi1/RC_CG_HIER_INST202/enable]  \
  [get_pins spi1/RC_CG_HIER_INST204/enable]  \
  [get_pins system0/RC_CG_HIER_INST211/enable]  \
  [get_pins system0/RC_CG_HIER_INST212/enable]  \
  [get_pins system0/RC_CG_HIER_INST213/enable]  \
  [get_pins system0/RC_CG_HIER_INST214/enable]  \
  [get_pins system0/RC_CG_HIER_INST215/enable]  \
  [get_pins system0/RC_CG_HIER_INST216/enable]  \
  [get_pins system0/RC_CG_HIER_INST217/enable]  \
  [get_pins system0/RC_CG_HIER_INST218/enable]  \
  [get_pins system0/RC_CG_HIER_INST219/enable]  \
  [get_pins system0/RC_CG_HIER_INST220/enable]  \
  [get_pins system0/RC_CG_HIER_INST221/enable]  \
  [get_pins system0/RC_CG_HIER_INST222/enable]  \
  [get_pins system0/RC_CG_HIER_INST223/enable]  \
  [get_pins system0/RC_CG_HIER_INST224/enable]  \
  [get_pins system0/RC_CG_HIER_INST225/enable]  \
  [get_pins system0/RC_CG_HIER_INST226/enable]  \
  [get_pins system0/RC_CG_HIER_INST227/enable]  \
  [get_pins system0/RC_CG_HIER_INST228/enable]  \
  [get_pins system0/RC_CG_HIER_INST229/enable]  \
  [get_pins system0/RC_CG_HIER_INST230/enable]  \
  [get_pins system0/RC_CG_HIER_INST231/enable]  \
  [get_pins system0/RC_CG_HIER_INST232/enable]  \
  [get_pins system0/RC_CG_HIER_INST233/enable]  \
  [get_pins system0/RC_CG_HIER_INST234/enable]  \
  [get_pins system0/RC_CG_HIER_INST235/enable]  \
  [get_pins system0/RC_CG_HIER_INST236/enable]  \
  [get_pins system0/RC_CG_HIER_INST237/enable]  \
  [get_pins system0/RC_CG_HIER_INST238/enable]  \
  [get_pins system0/RC_CG_HIER_INST239/enable]  \
  [get_pins system0/RC_CG_HIER_INST240/enable]  \
  [get_pins timer0/RC_CG_HIER_INST246/enable]  \
  [get_pins timer0/RC_CG_HIER_INST247/enable]  \
  [get_pins timer0/RC_CG_HIER_INST248/enable]  \
  [get_pins timer0/RC_CG_HIER_INST249/enable]  \
  [get_pins timer0/RC_CG_HIER_INST250/enable]  \
  [get_pins timer0/RC_CG_HIER_INST251/enable]  \
  [get_pins timer0/RC_CG_HIER_INST252/enable]  \
  [get_pins timer0/RC_CG_HIER_INST253/enable]  \
  [get_pins timer0/RC_CG_HIER_INST254/enable]  \
  [get_pins timer0/RC_CG_HIER_INST255/enable]  \
  [get_pins timer0/RC_CG_HIER_INST256/enable]  \
  [get_pins timer0/RC_CG_HIER_INST257/enable]  \
  [get_pins timer0/RC_CG_HIER_INST258/enable]  \
  [get_pins timer0/RC_CG_HIER_INST259/enable]  \
  [get_pins timer0/RC_CG_HIER_INST260/enable]  \
  [get_pins timer0/RC_CG_HIER_INST261/enable]  \
  [get_pins timer0/RC_CG_HIER_INST263/enable]  \
  [get_pins timer1/RC_CG_HIER_INST266/enable]  \
  [get_pins timer1/RC_CG_HIER_INST267/enable]  \
  [get_pins timer1/RC_CG_HIER_INST268/enable]  \
  [get_pins timer1/RC_CG_HIER_INST269/enable]  \
  [get_pins timer1/RC_CG_HIER_INST270/enable]  \
  [get_pins timer1/RC_CG_HIER_INST271/enable]  \
  [get_pins timer1/RC_CG_HIER_INST272/enable]  \
  [get_pins timer1/RC_CG_HIER_INST273/enable]  \
  [get_pins timer1/RC_CG_HIER_INST274/enable]  \
  [get_pins timer1/RC_CG_HIER_INST275/enable]  \
  [get_pins timer1/RC_CG_HIER_INST276/enable]  \
  [get_pins timer1/RC_CG_HIER_INST277/enable]  \
  [get_pins timer1/RC_CG_HIER_INST278/enable]  \
  [get_pins timer1/RC_CG_HIER_INST279/enable]  \
  [get_pins timer1/RC_CG_HIER_INST280/enable]  \
  [get_pins timer1/RC_CG_HIER_INST281/enable]  \
  [get_pins timer1/RC_CG_HIER_INST283/enable]  \
  [get_pins uart0/RC_CG_HIER_INST284/enable]  \
  [get_pins uart0/RC_CG_HIER_INST285/enable]  \
  [get_pins uart0/RC_CG_HIER_INST286/enable]  \
  [get_pins uart0/RC_CG_HIER_INST288/enable]  \
  [get_pins uart1/RC_CG_HIER_INST299/enable]  \
  [get_pins uart1/RC_CG_HIER_INST300/enable]  \
  [get_pins uart1/RC_CG_HIER_INST301/enable]  \
  [get_pins uart1/RC_CG_HIER_INST303/enable] ]
group_path -weight 1.000000 -name cg_enable_group_smclk -through [list \
  [get_pins afe0/adc_fsm/counter/RC_CG_HIER_INST35/enable]  \
  [get_pins afe0/adc_fsm/fsm/RC_CG_HIER_INST36/enable]  \
  [get_pins i2c0/CGMaster/RC_CG_HIER_INST140/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST127/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST134/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins i2c1/CGMaster/RC_CG_HIER_INST154/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST141/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST148/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST151/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST152/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST153/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST171/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST172/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST175/enable]  \
  [get_pins spi0/RC_CG_HIER_INST176/enable]  \
  [get_pins spi0/RC_CG_HIER_INST177/enable]  \
  [get_pins spi0/RC_CG_HIER_INST188/enable]  \
  [get_pins spi0/RC_CG_HIER_INST190/enable]  \
  [get_pins spi0/RC_CG_HIER_INST191/enable]  \
  [get_pins spi0/RC_CG_HIER_INST192/enable]  \
  [get_pins spi0/RC_CG_HIER_INST193/enable]  \
  [get_pins spi0/RC_CG_HIER_INST194/enable]  \
  [get_pins spi1/RC_CG_HIER_INST203/enable]  \
  [get_pins spi1/RC_CG_HIER_INST205/enable]  \
  [get_pins spi1/RC_CG_HIER_INST206/enable]  \
  [get_pins spi1/RC_CG_HIER_INST207/enable]  \
  [get_pins spi1/RC_CG_HIER_INST208/enable]  \
  [get_pins spi1/RC_CG_HIER_INST209/enable]  \
  [get_pins uart0/RC_CG_HIER_INST287/enable]  \
  [get_pins uart0/RC_CG_HIER_INST289/enable]  \
  [get_pins uart0/RC_CG_HIER_INST290/enable]  \
  [get_pins uart0/RC_CG_HIER_INST291/enable]  \
  [get_pins uart0/RC_CG_HIER_INST292/enable]  \
  [get_pins uart0/RC_CG_HIER_INST293/enable]  \
  [get_pins uart0/RC_CG_HIER_INST294/enable]  \
  [get_pins uart0/RC_CG_HIER_INST295/enable]  \
  [get_pins uart0/RC_CG_HIER_INST296/enable]  \
  [get_pins uart0/RC_CG_HIER_INST297/enable]  \
  [get_pins uart0/RC_CG_HIER_INST298/enable]  \
  [get_pins uart1/RC_CG_HIER_INST302/enable]  \
  [get_pins uart1/RC_CG_HIER_INST304/enable]  \
  [get_pins uart1/RC_CG_HIER_INST305/enable]  \
  [get_pins uart1/RC_CG_HIER_INST306/enable]  \
  [get_pins uart1/RC_CG_HIER_INST307/enable]  \
  [get_pins uart1/RC_CG_HIER_INST308/enable]  \
  [get_pins uart1/RC_CG_HIER_INST309/enable]  \
  [get_pins uart1/RC_CG_HIER_INST310/enable]  \
  [get_pins uart1/RC_CG_HIER_INST311/enable]  \
  [get_pins uart1/RC_CG_HIER_INST312/enable]  \
  [get_pins uart1/RC_CG_HIER_INST313/enable]  \
  [get_pins afe0/adc_fsm/counter/RC_CG_HIER_INST35/enable]  \
  [get_pins afe0/adc_fsm/fsm/RC_CG_HIER_INST36/enable]  \
  [get_pins i2c0/CGMaster/RC_CG_HIER_INST140/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST127/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST134/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins i2c1/CGMaster/RC_CG_HIER_INST154/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST141/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST148/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST151/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST152/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST153/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST171/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST172/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST175/enable]  \
  [get_pins spi0/RC_CG_HIER_INST176/enable]  \
  [get_pins spi0/RC_CG_HIER_INST177/enable]  \
  [get_pins spi0/RC_CG_HIER_INST188/enable]  \
  [get_pins spi0/RC_CG_HIER_INST190/enable]  \
  [get_pins spi0/RC_CG_HIER_INST191/enable]  \
  [get_pins spi0/RC_CG_HIER_INST192/enable]  \
  [get_pins spi0/RC_CG_HIER_INST193/enable]  \
  [get_pins spi0/RC_CG_HIER_INST194/enable]  \
  [get_pins spi1/RC_CG_HIER_INST203/enable]  \
  [get_pins spi1/RC_CG_HIER_INST205/enable]  \
  [get_pins spi1/RC_CG_HIER_INST206/enable]  \
  [get_pins spi1/RC_CG_HIER_INST207/enable]  \
  [get_pins spi1/RC_CG_HIER_INST208/enable]  \
  [get_pins spi1/RC_CG_HIER_INST209/enable]  \
  [get_pins uart0/RC_CG_HIER_INST287/enable]  \
  [get_pins uart0/RC_CG_HIER_INST289/enable]  \
  [get_pins uart0/RC_CG_HIER_INST290/enable]  \
  [get_pins uart0/RC_CG_HIER_INST291/enable]  \
  [get_pins uart0/RC_CG_HIER_INST292/enable]  \
  [get_pins uart0/RC_CG_HIER_INST293/enable]  \
  [get_pins uart0/RC_CG_HIER_INST294/enable]  \
  [get_pins uart0/RC_CG_HIER_INST295/enable]  \
  [get_pins uart0/RC_CG_HIER_INST296/enable]  \
  [get_pins uart0/RC_CG_HIER_INST297/enable]  \
  [get_pins uart0/RC_CG_HIER_INST298/enable]  \
  [get_pins uart1/RC_CG_HIER_INST302/enable]  \
  [get_pins uart1/RC_CG_HIER_INST304/enable]  \
  [get_pins uart1/RC_CG_HIER_INST305/enable]  \
  [get_pins uart1/RC_CG_HIER_INST306/enable]  \
  [get_pins uart1/RC_CG_HIER_INST307/enable]  \
  [get_pins uart1/RC_CG_HIER_INST308/enable]  \
  [get_pins uart1/RC_CG_HIER_INST309/enable]  \
  [get_pins uart1/RC_CG_HIER_INST310/enable]  \
  [get_pins uart1/RC_CG_HIER_INST311/enable]  \
  [get_pins uart1/RC_CG_HIER_INST312/enable]  \
  [get_pins uart1/RC_CG_HIER_INST313/enable]  \
  [get_pins afe0/adc_fsm/counter/RC_CG_HIER_INST35/enable]  \
  [get_pins afe0/adc_fsm/fsm/RC_CG_HIER_INST36/enable]  \
  [get_pins i2c0/CGMaster/RC_CG_HIER_INST140/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST127/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST134/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST137/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST138/enable]  \
  [get_pins i2c0/RC_CG_HIER_INST139/enable]  \
  [get_pins i2c1/CGMaster/RC_CG_HIER_INST154/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST141/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST148/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST151/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST152/enable]  \
  [get_pins i2c1/RC_CG_HIER_INST153/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST171/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST172/enable]  \
  [get_pins saradc0/RC_CG_HIER_INST175/enable]  \
  [get_pins spi0/RC_CG_HIER_INST176/enable]  \
  [get_pins spi0/RC_CG_HIER_INST177/enable]  \
  [get_pins spi0/RC_CG_HIER_INST188/enable]  \
  [get_pins spi0/RC_CG_HIER_INST190/enable]  \
  [get_pins spi0/RC_CG_HIER_INST191/enable]  \
  [get_pins spi0/RC_CG_HIER_INST192/enable]  \
  [get_pins spi0/RC_CG_HIER_INST193/enable]  \
  [get_pins spi0/RC_CG_HIER_INST194/enable]  \
  [get_pins spi1/RC_CG_HIER_INST203/enable]  \
  [get_pins spi1/RC_CG_HIER_INST205/enable]  \
  [get_pins spi1/RC_CG_HIER_INST206/enable]  \
  [get_pins spi1/RC_CG_HIER_INST207/enable]  \
  [get_pins spi1/RC_CG_HIER_INST208/enable]  \
  [get_pins spi1/RC_CG_HIER_INST209/enable]  \
  [get_pins uart0/RC_CG_HIER_INST287/enable]  \
  [get_pins uart0/RC_CG_HIER_INST289/enable]  \
  [get_pins uart0/RC_CG_HIER_INST290/enable]  \
  [get_pins uart0/RC_CG_HIER_INST291/enable]  \
  [get_pins uart0/RC_CG_HIER_INST292/enable]  \
  [get_pins uart0/RC_CG_HIER_INST293/enable]  \
  [get_pins uart0/RC_CG_HIER_INST294/enable]  \
  [get_pins uart0/RC_CG_HIER_INST295/enable]  \
  [get_pins uart0/RC_CG_HIER_INST296/enable]  \
  [get_pins uart0/RC_CG_HIER_INST297/enable]  \
  [get_pins uart0/RC_CG_HIER_INST298/enable]  \
  [get_pins uart1/RC_CG_HIER_INST302/enable]  \
  [get_pins uart1/RC_CG_HIER_INST304/enable]  \
  [get_pins uart1/RC_CG_HIER_INST305/enable]  \
  [get_pins uart1/RC_CG_HIER_INST306/enable]  \
  [get_pins uart1/RC_CG_HIER_INST307/enable]  \
  [get_pins uart1/RC_CG_HIER_INST308/enable]  \
  [get_pins uart1/RC_CG_HIER_INST309/enable]  \
  [get_pins uart1/RC_CG_HIER_INST310/enable]  \
  [get_pins uart1/RC_CG_HIER_INST311/enable]  \
  [get_pins uart1/RC_CG_HIER_INST312/enable]  \
  [get_pins uart1/RC_CG_HIER_INST313/enable] ]
group_path -weight 1.000000 -name cg_enable_group_mclk -through [list \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST44/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST45/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST46/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST47/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST50/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST51/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST52/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST53/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST54/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST55/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST56/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST57/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST58/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST59/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST60/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST61/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST62/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST63/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST64/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST65/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST66/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST67/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST68/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST69/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST70/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST71/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST72/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST73/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST74/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST75/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST76/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST77/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST78/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST79/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST80/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST81/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST82/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST83/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST84/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST85/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST86/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST87/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST88/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST89/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST90/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST48/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST49/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST91/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST92/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST93/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST94/enable]  \
  [get_pins core/RC_CG_HIER_INST37/enable]  \
  [get_pins core/RC_CG_HIER_INST38/enable]  \
  [get_pins core/RC_CG_HIER_INST39/enable]  \
  [get_pins core/RC_CG_HIER_INST40/enable]  \
  [get_pins core/RC_CG_HIER_INST41/enable]  \
  [get_pins core/RC_CG_HIER_INST42/enable]  \
  [get_pins core/RC_CG_HIER_INST43/enable]  \
  [get_pins npu0/RC_CG_HIER_INST155/enable]  \
  [get_pins npu0/RC_CG_HIER_INST156/enable]  \
  [get_pins npu0/RC_CG_HIER_INST157/enable]  \
  [get_pins npu0/RC_CG_HIER_INST158/enable]  \
  [get_pins npu0/RC_CG_HIER_INST159/enable]  \
  [get_pins npu0/RC_CG_HIER_INST160/enable]  \
  [get_pins npu0/RC_CG_HIER_INST161/enable]  \
  [get_pins npu0/RC_CG_HIER_INST170/enable]  \
  [get_pins core/RC_CG_HIER_INST37/enable]  \
  [get_pins core/RC_CG_HIER_INST38/enable]  \
  [get_pins core/RC_CG_HIER_INST39/enable]  \
  [get_pins core/RC_CG_HIER_INST40/enable]  \
  [get_pins core/RC_CG_HIER_INST41/enable]  \
  [get_pins core/RC_CG_HIER_INST42/enable]  \
  [get_pins core/RC_CG_HIER_INST43/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST44/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST45/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST46/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST47/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST48/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST49/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST50/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST51/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST52/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST53/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST54/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST55/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST56/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST57/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST58/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST59/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST60/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST61/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST62/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST63/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST64/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST65/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST66/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST67/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST68/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST69/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST70/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST71/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST72/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST73/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST74/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST75/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST76/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST77/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST78/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST79/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST80/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST81/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST82/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST83/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST84/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST85/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST86/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST87/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST88/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST89/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST90/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST91/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST92/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST93/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST94/enable]  \
  [get_pins npu0/RC_CG_HIER_INST155/enable]  \
  [get_pins npu0/RC_CG_HIER_INST156/enable]  \
  [get_pins npu0/RC_CG_HIER_INST157/enable]  \
  [get_pins npu0/RC_CG_HIER_INST158/enable]  \
  [get_pins npu0/RC_CG_HIER_INST159/enable]  \
  [get_pins npu0/RC_CG_HIER_INST160/enable]  \
  [get_pins npu0/RC_CG_HIER_INST161/enable]  \
  [get_pins npu0/RC_CG_HIER_INST170/enable]  \
  [get_pins core/RC_CG_HIER_INST37/enable]  \
  [get_pins core/RC_CG_HIER_INST38/enable]  \
  [get_pins core/RC_CG_HIER_INST39/enable]  \
  [get_pins core/RC_CG_HIER_INST40/enable]  \
  [get_pins core/RC_CG_HIER_INST41/enable]  \
  [get_pins core/RC_CG_HIER_INST42/enable]  \
  [get_pins core/RC_CG_HIER_INST43/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST44/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST45/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST46/enable]  \
  [get_pins core/csr_unit_inst/RC_CG_HIER_INST47/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST48/enable]  \
  [get_pins core/datapath_inst/RC_CG_HIER_INST49/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST50/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST51/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST52/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST53/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST54/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST55/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST56/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST57/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST58/enable]  \
  [get_pins core/datapath_inst/mainalu/divider/RC_CG_HIER_INST59/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST60/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST61/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST62/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST63/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST64/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST65/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST66/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST67/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST68/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST69/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST70/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST71/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST72/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST73/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST74/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST75/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST76/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST77/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST78/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST79/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST80/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST81/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST82/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST83/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST84/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST85/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST86/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST87/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST88/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST89/enable]  \
  [get_pins core/datapath_inst/rf/RC_CG_HIER_INST90/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST91/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST92/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST93/enable]  \
  [get_pins core/irq_handler_inst/RC_CG_HIER_INST94/enable]  \
  [get_pins npu0/RC_CG_HIER_INST155/enable]  \
  [get_pins npu0/RC_CG_HIER_INST156/enable]  \
  [get_pins npu0/RC_CG_HIER_INST157/enable]  \
  [get_pins npu0/RC_CG_HIER_INST158/enable]  \
  [get_pins npu0/RC_CG_HIER_INST159/enable]  \
  [get_pins npu0/RC_CG_HIER_INST160/enable]  \
  [get_pins npu0/RC_CG_HIER_INST161/enable]  \
  [get_pins npu0/RC_CG_HIER_INST170/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_sck0 -through [list \
  [get_pins spi0/RC_CG_HIER_INST195/enable]  \
  [get_pins spi0/RC_CG_HIER_INST195/enable]  \
  [get_pins spi0/RC_CG_HIER_INST195/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_sck1 -through [list \
  [get_pins spi1/RC_CG_HIER_INST210/enable]  \
  [get_pins spi1/RC_CG_HIER_INST210/enable]  \
  [get_pins spi1/RC_CG_HIER_INST210/enable] ]
group_path -weight 1.000000 -name cg_enable_group_default -through [list \
  [get_pins system0/RC_CG_HIER_INST241/enable]  \
  [get_pins system0/RC_CG_HIER_INST242/enable]  \
  [get_pins system0/RC_CG_HIER_INST243/enable]  \
  [get_pins timer0/RC_CG_HIER_INST244/enable]  \
  [get_pins timer0/RC_CG_HIER_INST245/enable]  \
  [get_pins timer1/RC_CG_HIER_INST264/enable]  \
  [get_pins timer1/RC_CG_HIER_INST265/enable]  \
  [get_pins system0/RC_CG_HIER_INST241/enable]  \
  [get_pins system0/RC_CG_HIER_INST242/enable]  \
  [get_pins system0/RC_CG_HIER_INST243/enable]  \
  [get_pins timer0/RC_CG_HIER_INST244/enable]  \
  [get_pins timer0/RC_CG_HIER_INST245/enable]  \
  [get_pins timer1/RC_CG_HIER_INST264/enable]  \
  [get_pins timer1/RC_CG_HIER_INST265/enable]  \
  [get_pins system0/RC_CG_HIER_INST241/enable]  \
  [get_pins system0/RC_CG_HIER_INST242/enable]  \
  [get_pins system0/RC_CG_HIER_INST243/enable]  \
  [get_pins timer0/RC_CG_HIER_INST244/enable]  \
  [get_pins timer0/RC_CG_HIER_INST245/enable]  \
  [get_pins timer1/RC_CG_HIER_INST264/enable]  \
  [get_pins timer1/RC_CG_HIER_INST265/enable] ]
group_path -weight 1.000000 -name cg_enable_group_clk_hfxt -through [list \
  [get_pins timer0/RC_CG_HIER_INST262/enable]  \
  [get_pins timer1/RC_CG_HIER_INST282/enable]  \
  [get_pins timer0/RC_CG_HIER_INST262/enable]  \
  [get_pins timer1/RC_CG_HIER_INST282/enable]  \
  [get_pins timer0/RC_CG_HIER_INST262/enable]  \
  [get_pins timer1/RC_CG_HIER_INST282/enable] ]
set_clock_gating_check -setup 0.0 
set_max_transition 0.5 [current_design]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports resetn_in]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[7]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[6]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[5]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[4]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[3]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[2]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[1]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt1_in[0]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[7]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[6]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[5]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[4]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[3]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[2]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[1]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt2_in[0]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[7]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[6]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[5]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[4]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[3]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[2]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[1]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt3_in[0]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[7]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[6]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[5]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[4]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[3]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[2]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[1]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {prt4_in[0]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports dsadc_conv_done]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports saradc_rdy]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[9]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[8]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[7]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[6]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[5]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[4]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[3]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[2]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[1]}]
set_driving_cell -lib_cell INVX1MA10TH -library scadv10_cln65gp_hvt_tt_1p0v_25c -pin "Y" [get_ports {saradc_data[0]}]
set_wire_load_mode "enclosed"
set_dont_touch [get_nets {npu0/Decision[15]}]
set_dont_use false [get_lib_cells scadv10_cln65gp_hvt_tt_1p0v_25c/TIEHIX1MA10TH]
set_dont_use false [get_lib_cells scadv10_cln65gp_hvt_tt_1p0v_25c/TIELOX1MA10TH]
