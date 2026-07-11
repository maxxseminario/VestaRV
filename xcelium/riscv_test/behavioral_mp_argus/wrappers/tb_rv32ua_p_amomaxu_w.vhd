entity tb_rv32ua_p_amomaxu_w is end tb_rv32ua_p_amomaxu_w;
architecture behavioral of tb_rv32ua_p_amomaxu_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/rv32ua-p-amomaxu_w.rcf");
end architecture;
