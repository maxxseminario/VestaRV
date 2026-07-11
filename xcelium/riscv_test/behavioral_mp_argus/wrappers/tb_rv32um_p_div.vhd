entity tb_rv32um_p_div is end tb_rv32um_p_div;
architecture behavioral of tb_rv32um_p_div is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32um-p-div.rcf");
end architecture;
