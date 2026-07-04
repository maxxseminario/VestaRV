entity tb_rv32ui_p_auipc is end tb_rv32ui_p_auipc;
architecture behavioral of tb_rv32ui_p_auipc is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-auipc.rcf");
end architecture;
