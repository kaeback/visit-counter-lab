package com.example;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;
import java.io.IOException;
import java.nio.file.*;

@SpringBootApplication
@RestController
public class VisitCounterApplication {
    private static final Path COUNT_FILE = Paths.get("/data/count.txt");

    public static void main(String[] args) throws Exception {
        Files.createDirectories(COUNT_FILE.getParent());
        SpringApplication.run(VisitCounterApplication.class, args);
    }

    @GetMapping("/")
    public String visit() throws IOException {
        long count = readCount() + 1;
        writeCount(count);
        return "방문 횟수: " + count + "\n";
    }
    @GetMapping("/count")
    public String count() throws IOException {
        return "현재 카운트: " + readCount() + "\n";
    }

    @GetMapping("/reset")
    public String reset() throws IOException {
        writeCount(0);
        return "카운터를 초기화했습니다.\n";
    }

    private long readCount() {
        try { return Long.parseLong(Files.readString(COUNT_FILE).trim()); }
        catch (Exception e) { return 0; }
    }

    private void writeCount(long n) throws IOException {
        Files.writeString(COUNT_FILE, String.valueOf(n));
    }
}
