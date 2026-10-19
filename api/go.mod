module github.com/kentayamada-dev/playground/api

go 1.26.0

// osv-scanner は toolchain の版を stdlib の版として検査し、なければ go の行の古い版で検査して脆弱性を報告するため
// https://github.com/google/osv-scalibr/blob/3090dbb7aaa24ce7a807899e7f16baa8b802a828/extractor/filesystem/language/golang/gomod/gomod.go#L189-L199
toolchain go1.27.2
