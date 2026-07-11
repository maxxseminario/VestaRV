entity tb_rv32ui_p_shmem is end tb_rv32ui_p_shmem;
architecture behavioral of tb_rv32ui_p_shmem is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32ui-p-shmem.rcf");
end architecture;
