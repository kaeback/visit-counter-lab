package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;

@SpringBootApplication
@RestController
public class VisitCounterApplication {

    private final VisitCountRepository repo;

    public VisitCounterApplication(VisitCountRepository repo) {
        this.repo = repo;
    }

    public static void main(String[] args) {
        SpringApplication.run(VisitCounterApplication.class, args);
    }
    @GetMapping("/")
    public String visit() {
        VisitCount vc = repo.findAll().stream().findFirst()
            .orElseGet(() -> {
                VisitCount v = new VisitCount(); return repo.save(v); });
        vc.setCount(vc.getCount() + 1);
        repo.save(vc);
        return "방문 횟수: " + vc.getCount() + "\n";
    }
    @GetMapping("/count")
    public String count() {
        long c = repo.findAll().stream().findFirst()
            .map(v -> v.getCount()).orElse(0L);
        return "현재 카운트: " + c + "\n";
    }
    @GetMapping("/reset")
    public String reset() {
        repo.findAll().stream().findFirst().ifPresent(v -> {
            v.setCount(0); repo.save(v);
        });
        return "카운터를 초기화했습니다.\n";
    }
}
