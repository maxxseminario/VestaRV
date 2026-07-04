entity tb_rv32ui_p_sb is end tb_rv32ui_p_sb;
architecture behavioral of tb_rv32ui_p_sb is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxxrv32ui-p-sb.rcf");
end architecture;
