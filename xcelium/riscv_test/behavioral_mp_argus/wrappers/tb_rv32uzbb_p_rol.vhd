entity tb_rv32uzbb_p_rol is end tb_rv32uzbb_p_rol;
architecture behavioral of tb_rv32uzbb_p_rol is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32uzbb-p-rol.rcf");
end architecture;
