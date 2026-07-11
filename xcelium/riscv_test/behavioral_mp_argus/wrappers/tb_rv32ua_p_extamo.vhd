entity tb_rv32ua_p_extamo is end tb_rv32ua_p_extamo;
architecture behavioral of tb_rv32ua_p_extamo is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32ua-p-extamo.rcf");
end architecture;
