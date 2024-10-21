BEGIN {
    #
    # BPF
    # from Fedora
    force["CONFIG_ARCH_WANT_DEFAULT_BPF_JIT"] = ""
    force["CONFIG_BPF_EVENTS"] = ""
    force["CONFIG_BPFILTER"] = "NULL"
    force["CONFIG_BPF_JIT_ALWAYS_ON"] = "y"
    force["CONFIG_BPF_JIT_DEFAULT_ON"] = ""
    force["CONFIG_BPF_JIT"] = "y"
    force["CONFIG_BPF_KPROBE_OVERRIDE"] = "NULL"
    force["CONFIG_BPF_LIRC_MODE2"] = "y"
    force["CONFIG_BPF_LSM"] = "y"
    force["CONFIG_BPF"] = "NULL"
    force["CONFIG_BPF_PRELOAD_UMD"] = "m"
    force["CONFIG_BPF_PRELOAD"] = "y"
    force["CONFIG_BPF_STREAM_PARSER"] = "y"
    force["CONFIG_BPF_UNPRIV_DEFAULT_OFF"] = "y"
    force["CONFIG_HAVE_EBPF_JIT"] = ""
    force["CONFIG_HID_BPF"] = "y"
    force["CONFIG_IPV6_SEG6_BPF"] = ""
    force["CONFIG_LWTUNNEL_BPF"] = "y"
    force["CONFIG_NBPFAXI_DMA"] = "NULL"
    force["CONFIG_NET_ACT_BPF"] = "m"
    force["CONFIG_NET_CLS_BPF"] = "m"
    force["CONFIG_NETFILTER_BPF_LINK"] = ""
    force["CONFIG_NETFILTER_XT_MATCH_BPF"] = "m"
    force["CONFIG_TEST_BPF"] = "m"

    # BTF
    # from Fedora
    force["CONFIG_DEBUG_INFO_BTF_MODULES"] = "y"
    force["CONFIG_MODULE_ALLOW_BTF_MISMATCH"] = "NULL"
    force["CONFIG_PAHOLE_HAS_SPLIT_BTF"] = ""
    force["CONFIG_PROBE_EVENTS_BTF_ARGS"] = "y"

    # FTRACE
    # from Fedora
    force["CONFIG_DYNAMIC_FTRACE"] = "y"
    force["CONFIG_FTRACE_MCOUNT_RECORD"] = "y"
    force["CONFIG_FTRACE_RECORD_RECURSION"] = "NULL"
    force["CONFIG_FTRACE_SORT_STARTUP_TEST"] = "NULL"
    force["CONFIG_FTRACE_STARTUP_TEST"] = "NULL"
    force["CONFIG_FTRACE_SYSCALLS"] = "y"
    force["CONFIG_FTRACE_VALIDATE_RCU_IS_WATCHING"] = "NULL"
    force["CONFIG_FUNCTION_TRACER"] = "y"
    force["CONFIG_GCC_SUPPORTS_DYNAMIC_FTRACE_WITH_ARGS"] = ""
    force["CONFIG_HAVE_DYNAMIC_FTRACE"] = ""
    force["CONFIG_HAVE_DYNAMIC_FTRACE_WITH_ARGS"] = ""
    force["CONFIG_HAVE_FTRACE_MCOUNT_RECORD"] = ""
    force["CONFIG_HAVE_SAMPLE_FTRACE_DIRECT"] = ""
    force["CONFIG_HAVE_SAMPLE_FTRACE_DIRECT_MULTI"] = ""
    force["CONFIG_PSTORE_FTRACE"] = "NULL"
    force["CONFIG_STM_SOURCE_FTRACE"] = "NULL"

    # LSM
    # from Fedora
    force["CONFIG_IIO_ST_LSM6DSX_I2C"] = ""
    force["CONFIG_IIO_ST_LSM6DSX_SPI"] = ""
    force["CONFIG_IMA_LSM_RULES"] = "y"
    force["CONFIG_LSM_MMAP_MIN_ADDR"] = "65535"
    force["CONFIG_SECURITY_LOCKDOWN_LSM_EARLY"] = "y"

    # SYSCALL
    # from Fedora
    force["CONFIG_ARCH_HAS_SYSCALL_WRAPPER"] = ""
    force["CONFIG_GENERIC_TIME_VSYSCALL"] = ""
    force["CONFIG_HAVE_ARCH_AUDITSYSCALL"] = ""
    force["CONFIG_HAVE_SYSCALL_TRACEPOINTS"] = ""
    force["CONFIG_MODIFY_LDT_SYSCALL"] = "y"
    force["CONFIG_PCI_SYSCALL"] = ""
    force["CONFIG_SGETMASK_SYSCALL"] = "y"
}
