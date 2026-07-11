entity tb_rv32ua_p_shamo is end tb_rv32ua_p_shamo;
architecture behavioral of tb_rv32ua_p_shamo is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32ua-p-shamo.rcf");
end architecture;
