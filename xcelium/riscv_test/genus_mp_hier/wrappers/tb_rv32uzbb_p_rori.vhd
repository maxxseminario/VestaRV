entity tb_rv32uzbb_p_rori is end tb_rv32uzbb_p_rori;
architecture behavioral of tb_rv32uzbb_p_rori is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbb-p-rori.rcf");
end architecture;
