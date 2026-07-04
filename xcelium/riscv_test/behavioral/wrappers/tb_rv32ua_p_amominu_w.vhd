entity tb_rv32ua_p_amominu_w is end tb_rv32ua_p_amominu_w;
architecture behavioral of tb_rv32ua_p_amominu_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/rv32ua-p-amominu_w.rcf");
end architecture;
