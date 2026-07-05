entity tb_rv32uzbs_p_bseti is end tb_rv32uzbs_p_bseti;
architecture behavioral of tb_rv32uzbs_p_bseti is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32uzbs-p-bseti.rcf");
end architecture;
