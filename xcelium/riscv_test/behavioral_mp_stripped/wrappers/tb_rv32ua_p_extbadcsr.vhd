entity tb_rv32ua_p_extbadcsr is end tb_rv32ua_p_extbadcsr;
architecture behavioral of tb_rv32ua_p_extbadcsr is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/rv32ua-p-extbadcsr.rcf");
end architecture;
