BEGIN {
    if (ARGC != 4 ) {
        printf("%s - wrong number of arguments, expected 4 got %d\n", ARGV[0], ARGC - 1)
        printf("\n<copy>[y|m|NULL|ADD] <from reference file> <into target file>\n")

        exit(1)
    }

#printf("%s: copy=%s, lh=%s, rh=%s\n", ARGV[0], ARGV[1], ARGV[2], ARGV[3]) > "/dev/stderr"
    copy = ARGV[1]
    lh = ARGV[2]
    rh = ARGV[3]
    lineno = 0

    force["CONFIG_DEBUG_INFO_BTF"] = "y"
    force["CONFIG_DEBUG_INFO_REDUCED"] = "n"
    force["CONFIG_EFI_GENERIC_STUB"] = "y"
    force["CONFIG_EFI_ZBOOT"] = "y"
    force["CONFIG_KERNEL_GZIP"] = "y"
    force["CONFIG_MODULE_SIG"] = "y"
    force["CONFIG_IMA_APPRAISE_MODSIG"] = "y"

    while (getline < lh > 0) {
        lhLine[++lineno] = $0

        switch ($0) {
        case /^# CONFIG_/:
            lhKey[$2] = "NULL"
            break
        case /^CONFIG_/:
            split($0, a, /=/)
            lhKey[a[1]] = a[2]
            break
        }
    }
    close(lh)

    lineno = 0
    while (getline < rh > 0) {
        rhLine[++lineno] = $0

        switch ($0) {
        case /^# CONFIG_/:
            rhKey[$2] = "NULL"
            break
        case /^CONFIG_/:
            split($0, a, /=/)
            rhKey[a[1]] = a[2]
            break
        }
    }
    close(rh)

    for (key in rhKey) {
        if (copy != "ADD") {
            if (lhKey[key] == copy) {
                if (rhKey[key] != lhKey[key]) {
                    printf("%s - changed from %s to %s\n", key, rhKey[key], lhKey[key]) > "/dev/stderr"
                    
                    rhKey[key] = lhKey[key]
                }
            }
        } else {
            printf("%s - unchanged %s\n", key, rhKey[key]) > "/dev/stderr"
        }
    }

    for (key in lhKey) {
        if (length(rhKey[key]) == 0) {
            printf("added key %s value %s\n", key, lhKey[key]) > "/dev/stderr"

            rhKey[key] = lhKey[key]
        }
    }

    for (key in force) {
        printf("forced key %s value %s\n", key, force[key]) > "/dev/stderr"

        rhKey[key] = force[key]
    }

    # END {}
    printf("# arm64\n")

    for (key in rhKey) {
        if (rhKey[key] == "NULL")
            printf("# %s is not set\n", key)
        else
            printf("%s=%s\n", key, rhKey[key])
    }

    exit(0)
}
