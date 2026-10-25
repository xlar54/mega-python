;=======================================================================================
; DMAgic helpers (F018B enhanced lists, patched in place).
;
; F018B job layout (after the option bytes, which end with $00):
;     +0  command   ($00 copy, $03 fill)
;     +1  count     (word)
;     +3  source    (word + bank byte; for a fill, the low byte is the fill value)
;     +6  dest      (word + bank byte)
;     +9  sub-command
;     +10 modulo    (word)
; Option $80/$81 give the source/dest megabyte (address bits 20-27); the bank byte
; holds address bits 16-19. A copy must not cross a megabyte boundary.
;=======================================================================================

dma_job:
        .byte DMAOPT_F018B
        .byte DMAOPT_SRC_MB
dmaj_src_mb:
        .byte 0
        .byte DMAOPT_DST_MB
dmaj_dst_mb:
        .byte 0
        .byte DMAOPT_END
dmaj_cmd:
        .byte DMACMD_COPY
dmaj_count:
        .word 0
dmaj_src:
        .word 0
dmaj_src_bank:
        .byte 0
dmaj_dst:
        .word 0
dmaj_dst_bank:
        .byte 0
        .byte 0
        .word 0

dma_go:
        lda #0
        sta DMA_ADDRMB
        sta DMA_ADDRBANK
        lda #>dma_job
        sta DMA_ADDRMSB
        lda #<dma_job
        sta DMA_ADDRLSB_ETRIG
        rts

; dma_copy: t0 bytes from 28-bit fp0 to 28-bit fp1 (t0 > 0)
dma_copy:
        lda #DMACMD_COPY
        sta dmaj_cmd
        lda fp0
        sta dmaj_src
        lda fp0+1
        sta dmaj_src+1
        lda fp0+2
        and #$0f
        sta dmaj_src_bank
        lda fp0+3
        asl
        asl
        asl
        asl
        sta dmaj_src_mb
        lda fp0+2
        lsr
        lsr
        lsr
        lsr
        ora dmaj_src_mb
        sta dmaj_src_mb
        bra dma_set_dst

; dma_fill: A = value, t0 bytes at 28-bit fp1 (t0 > 0)
dma_fill:
        sta dmaj_src
        lda #DMACMD_FILL
        sta dmaj_cmd
        lda #0
        sta dmaj_src+1
        sta dmaj_src_bank
        sta dmaj_src_mb
dma_set_dst:
        lda t0
        sta dmaj_count
        lda t0+1
        sta dmaj_count+1
        lda fp1
        sta dmaj_dst
        lda fp1+1
        sta dmaj_dst+1
        lda fp1+2
        and #$0f
        sta dmaj_dst_bank
        lda fp1+3
        asl
        asl
        asl
        asl
        sta dmaj_dst_mb
        lda fp1+2
        lsr
        lsr
        lsr
        lsr
        ora dmaj_dst_mb
        sta dmaj_dst_mb
        jmp dma_go
