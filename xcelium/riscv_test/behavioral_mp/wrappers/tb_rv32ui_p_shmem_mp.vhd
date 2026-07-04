entity tb_rv32ui_p_shmem_mp is end tb_rv32ui_p_shmem_mp;
architecture behavioral of tb_rv32ui_p_shmem_mp is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ui-p-shmem_mp.rcf");
end architecture;
