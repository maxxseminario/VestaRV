entity tb_rv32um_p_rem is end tb_rv32um_p_rem;
architecture behavioral of tb_rv32um_p_rem is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32um-p-rem.rcf");
end architecture;
