package main

import (
	"net/http"
	"testing"
)

func TestListenAndServe(t *testing.T) {
	t.Skip("gosec がテストのファイルを検査することを確かめるための検証用")

	if err := http.ListenAndServe("127.0.0.1:0", nil); err != nil {
		t.Fatal(err)
	}
}
