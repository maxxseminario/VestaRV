entity tb_rv32ua_p_extprobe is end tb_rv32ua_p_extprobe;
architecture behavioral of tb_rv32ua_p_extprobe is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ua-p-extprobe.rcf");
end architecture;
