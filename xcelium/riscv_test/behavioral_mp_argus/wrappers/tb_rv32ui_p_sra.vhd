entity tb_rv32ui_p_sra is end tb_rv32ui_p_sra;
architecture behavioral of tb_rv32ui_p_sra is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-sra.rcf");
end architecture;
