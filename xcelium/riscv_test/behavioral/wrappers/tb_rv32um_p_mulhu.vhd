entity tb_rv32um_p_mulhu is end tb_rv32um_p_mulhu;
architecture behavioral of tb_rv32um_p_mulhu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32um-p-mulhu.rcf");
end architecture;
