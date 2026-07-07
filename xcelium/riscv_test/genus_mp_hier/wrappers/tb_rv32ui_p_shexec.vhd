entity tb_rv32ui_p_shexec is end tb_rv32ui_p_shexec;
architecture behavioral of tb_rv32ui_p_shexec is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-shexec.rcf");
end architecture;
