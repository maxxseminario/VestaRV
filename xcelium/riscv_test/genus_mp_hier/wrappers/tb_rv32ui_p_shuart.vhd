entity tb_rv32ui_p_shuart is end tb_rv32ui_p_shuart;
architecture behavioral of tb_rv32ui_p_shuart is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-shuart.rcf");
end architecture;
