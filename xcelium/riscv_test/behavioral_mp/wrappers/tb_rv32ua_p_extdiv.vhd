entity tb_rv32ua_p_extdiv is end tb_rv32ua_p_extdiv;
architecture behavioral of tb_rv32ua_p_extdiv is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-extdiv.rcf");
end architecture;
