package main

import (
	"encoding/json"
	"log"
	"net/http"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /hello", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]string{"message": "hello from golang"}); err != nil {
			log.Printf("応答の書き込みに失敗しました: %v", err)
		}
	})

	log.Println("http://localhost:8080 で待ち受けています")
	log.Fatal(http.ListenAndServe(":8080", mux))
}
