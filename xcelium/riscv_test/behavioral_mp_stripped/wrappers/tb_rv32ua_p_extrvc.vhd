entity tb_rv32ua_p_extrvc is end tb_rv32ua_p_extrvc;
architecture behavioral of tb_rv32ua_p_extrvc is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-extrvc.rcf");
end architecture;
