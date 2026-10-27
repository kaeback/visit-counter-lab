package com.example;
import jakarta.persistence.*;
import java.time.LocalDateTime;
@Entity
@Table(name = "visit_count")
public class VisitCount {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private long count = 0;
    private LocalDateTime updatedAt = LocalDateTime.now();
    public long getCount() { return count; }
    public void setCount(long count) {
        this.count = count;
        this.updatedAt = LocalDateTime.now();
    }
}
