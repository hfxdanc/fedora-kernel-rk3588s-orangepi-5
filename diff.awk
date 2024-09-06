BEGIN {
    if (ARGC != 3 ) {
        printf("%s - wrong number of arguments, expected 3 got %d\n", ARGV[0], ARGC - 1)
        printf("\n<file> <file>\n")

        exit(1)
    }

    count = 0
    lh = ARGV[1]
    rh = ARGV[2]

    while (getline < lh > 0) {
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

    for (key in keys) {
        if (rhKey[key] != lhKey[key]) {
            printf("%s <%s< >%s>\n", key, lhKey[key], rhKey[key])

            count++
        }
    }

    for (key in lhKey)
        keys[key] = 0

    for (key in rhKey)
        keys[key] = 0

    for (key in keys) {
        if (rhKey[key] != lhKey[key]) {
            printf("%s <%s< >%s>\n", key, lhKey[key], rhKey[key])

            count++
        }
    }

    printf("Number of additional rhKeys keys = %d\n", count)

    exit(0)
}
