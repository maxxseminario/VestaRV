entity tb_rv32ui_p_afselv2 is end tb_rv32ui_p_afselv2;
architecture behavioral of tb_rv32ui_p_afselv2 is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ui-p-afselv2.rcf");
end architecture;
