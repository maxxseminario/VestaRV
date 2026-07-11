entity tb_rv32um_p_mulhsu is end tb_rv32um_p_mulhsu;
architecture behavioral of tb_rv32um_p_mulhsu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32um-p-mulhsu.rcf");
end architecture;
