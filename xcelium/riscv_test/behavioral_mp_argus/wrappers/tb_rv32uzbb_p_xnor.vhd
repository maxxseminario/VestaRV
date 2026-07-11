entity tb_rv32uzbb_p_xnor is end tb_rv32uzbb_p_xnor;
architecture behavioral of tb_rv32uzbb_p_xnor is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32uzbb-p-xnor.rcf");
end architecture;
