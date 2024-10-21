BEGIN {
    help="<file> <file>"
    helpMerge="<What CONFIG_key value type to copy> <from reference file> <into target file>"
    mode = "diff"

    for (i = 0; i < length(PROCINFO["argv"]); i++) {
        switch (PROCINFO["argv"][i]) {
        case /diff.awk/:
            mode = "diff"
            break
        case /common.awk/:
            mode = "common"
            break
        case /merge.awk/:
            mode = "merge"
            break
        }
    }

    printf("mode=%s\n\n", mode) > "/dev/stderr"

    if (mode == "merge") {
        if (ARGC != 4 ) {
            printf("%s.awk - wrong number of arguments, expected 3 got %d\n", mode, ARGC -1)
            printf("\nawk -f %s.awk %s\n", mode, helpMerge)

            exit(1)
        }

        switch (ARGV[1]) {
        case "y":
        case "n":
        case "m":
        case "NULL":
        case "ADD":
            copy = ARGV[1]
            break
        default:
            printf("awk -f %s.awk %s\n", mode, helpMerge)
            printf("\nWhat to copy must be one of <y|n|m|NULL|ADD>\n")

            exit(1)
        }

        lh = ARGV[2]
        rh = ARGV[3]
    } else {
        if (ARGC != 3 ) {
            printf("%s.awk - wrong number of arguments, expected 2 got %d\n", mode, ARGC - 1)
            printf("\nawk -f %s.awk %s\n", mode, help)

            exit(1)
        }

        lh = ARGV[1]
        rh = ARGV[2]
    }

    count = 0

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

    for (key in lhKey)
        keys[key] = 0

    for (key in rhKey)
        keys[key] = 0

    for (key in keys) {
        switch (mode) {
        case "diff":
            if (rhKey[key] != lhKey[key]) {
                printf("%s <%s< >%s>\n", key, lhKey[key], rhKey[key])

                count++
            }
            break
        case "common":
            if (rhKey[key] == lhKey[key])
                printf("%s <%s< >%s>\n", key, lhKey[key], rhKey[key])

            break
        case "merge":
            switch (copy) {
            case "y":
            case "n":
            case "m":
                if (rhKey[key] == copy) {
                    if (lhKey[key] != copy) {
                        if (length(lhKey[key]) > 0)
                            comment[key] = sprintf("changed from \"%s\"", lhKey[key])
                        else
                            comment[key] = sprintf("set to \"%s\"", copy)

                        lhKey[key] = copy
                    }
                }
                break
            case "ADD":
                 if (length(lhKey[key]) == 0) {
                    comment[key] = sprintf("added \"%s\"", rhKey[key])
                    lhKey[key] = rhKey[key]
                }
                break
            }

            switch (lhKey[key]) {
            case "":
                if (length(rhKey[key]) == 0)
                    dropped[key] = ""

                break
            case "NULL":
                printf("#%s is not set", key)
                if (length(comment[key]))
                    printf("\t# %s", comment[key])

                printf("\n")
                break
            default:
                printf("%s=%s", key, lhKey[key])
                if (length(comment[key]))
                    printf("\t# %s", comment[key])

                printf("\n")
            }

            break
        }
    }

    switch (mode) {
    case "merge":
        for (key in dropped) {
            printf("%s dropped\n", key) > "/dev/stderr"
        }

        break
    case "diff":
        printf("\nNumber of additional rhKeys keys = %d\n", count) > "/dev/stderr"
    }

    exit(0)
}
