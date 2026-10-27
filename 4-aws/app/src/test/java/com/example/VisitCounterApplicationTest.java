package com.example;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

// DB 없이 도는 단위 테스트 — 저장소(repo)를 가짜(mock)로 바꿔 끼운다
class VisitCounterApplicationTest {

    @Test
    void 기록이_없으면_현재_카운트는_0이다() {
        VisitCountRepository repo = mock(VisitCountRepository.class);
        when(repo.findAll()).thenReturn(List.of());

        assertEquals("현재 카운트: 0\n", new VisitCounterApplication(repo).count());
    }

    @Test
    void 방문하면_카운트가_1_오른다() {
        VisitCount saved = new VisitCount();
        saved.setCount(41);
        VisitCountRepository repo = mock(VisitCountRepository.class);
        when(repo.findAll()).thenReturn(List.of(saved));
        when(repo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        assertEquals("방문 횟수: 42\n", new VisitCounterApplication(repo).visit());
    }
}
