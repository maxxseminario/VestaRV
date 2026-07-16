entity tb_rv32ui_p_shnpu is end tb_rv32ui_p_shnpu;
architecture behavioral of tb_rv32ui_p_shnpu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shnpu.rcf");
end architecture;
