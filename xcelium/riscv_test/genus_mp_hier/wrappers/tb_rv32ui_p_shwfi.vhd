entity tb_rv32ui_p_shwfi is end tb_rv32ui_p_shwfi;
architecture behavioral of tb_rv32ui_p_shwfi is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shwfi.rcf");
end architecture;
