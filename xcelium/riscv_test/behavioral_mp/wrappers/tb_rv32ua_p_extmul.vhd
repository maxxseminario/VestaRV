entity tb_rv32ua_p_extmul is end tb_rv32ua_p_extmul;
architecture behavioral of tb_rv32ua_p_extmul is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-extmul.rcf");
end architecture;
