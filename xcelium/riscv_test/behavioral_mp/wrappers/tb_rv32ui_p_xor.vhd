entity tb_rv32ui_p_xor is end tb_rv32ui_p_xor;
architecture behavioral of tb_rv32ui_p_xor is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-xor.rcf");
end architecture;
