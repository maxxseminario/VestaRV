entity tb_rv32ui_p_shboot is end tb_rv32ui_p_shboot;
architecture behavioral of tb_rv32ui_p_shboot is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-shboot.rcf");
end architecture;
