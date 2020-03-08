;
; ReactionTime.asm
;
; Created: 02.02.2020 19:14:19
; Author : Алексей
;

; 1 Старт программы: разрешаем прерывание на кнопе PD2, таймер0 - 180 прерываний в сек, таймер1 - 1/256 просто счет без прерываний
; 2 Обработчик прерывания по сравнению на таймере0 работает автономно, просто обновляя цифры на индикаторе
; 3 Обработчик нажания кнопки: а) при первом нажатии - вычисляет псевдослучайную задержку, запрещает прерывание по кнопке, обнуляет цифры индикатора
; разрешает прерывание по сравнению на таймере1 на значении 3125, предделитель 1/256
; 4 при втором нажатии - гасит светодиод запрещает прерывания по сравнению на таймер1, выдает новые значения в цифры индикатора
; 5 Обработчик прерывания по сравнению на таймере1: считает до конца, в конце перенастраивается на 1/1 предделитель, разрешает прерывания от кнопки
; зажигает светодиод, во второй части прерывания просто считает миллисекунды


.include "tn2313adef.inc"

; Registers
.def debugDelayBits = r13
.def debugInt0Counter = r14
.def counterToInt0Enable = r15
.def temp   = r16
.def temp2  = r17
.def digit1 = r18
.def digit2 = r19
.def digit3 = r20
.def tickCount = r21
.def hundredsMillisec = r22
.def tensMilisec = r23
.def millisec = r24
.def seconds = r25

; Constants
.equ DOT_MASK = 0x80
.equ OUT_TO_FIRST_DIG = 0x10
.equ OUT_TO_SECOND_DIG = 0x20
.equ OUT_TO_THIRD_DIG = 0x40
.equ TIMER0_COUNTER = 173
.equ NEED_DOT_ON_FIRST_DIGIT = 0
.equ NEED_DOT_ON_SECOND_DIGIT = 1
.equ NEED_DOT_ON_THIRD_DIGIT = 2



.MACRO SETUP_TIMER1_COMPARE
	ldi @0, HIGH(@2)
	ldi @1, LOW(@2)
	out OCR1AH, @0
	out OCR1AL, @1
.ENDMACRO



.MACRO ENABLE_TIMER_INTERRUPT
	in @0, TIMSK
	sbr @0, (1 << @1)
	out TIMSK, @0
.ENDMACRO 



.MACRO DISABLE_TIMER_INTERRUPT
	in @0, TIMSK
	cbr @0, (1 << @1)
	out TIMSK, @0
.ENDMACRO 



.MACRO UPDATE_DIGIT
	ldi ZH, HIGH(digitToMask * 2)
	ldi ZL, LOW(digitToMask * 2)
	add ZL, @0
	clr @0
	adc ZH, @0
	lpm
	mov @1, r0
.ENDMACRO



; Interrupts vector
rjmp START
rjmp INT0_INT
.org 4
rjmp TIM1_COMPAR
.org 13
rjmp TIM0_COMPAR
.org 21



; refresh 7-segment indicator
TIM0_COMPAR:
	in temp, PORTD
	mov temp2, temp
	andi temp, 0xF0
	andi temp2, 0x0F

	;next digit
	lsl temp 

	cpi temp, OUT_TO_THIRD_DIG << 1
	sbrc temp, PORTB7
	; if was third digit - go to first digit
	ldi temp, OUT_TO_FIRST_DIG	

	or temp, temp2

	sbrc temp, PORTD4
	mov temp2, digit1

	sbrc temp, PORTD5
	mov temp2, digit2

	sbrc temp, PORTD6
	mov temp2, digit3

	out PORTD, temp
	out PORTB, temp2

	; for disable double pushing button
	brts tim0_compar_exit
	in temp, GIMSK
	sbrc temp, INT0
	rjmp tim0_compar_exit

	inc counterToInt0Enable
	mov temp, counterToInt0Enable 
	cpi temp, 10
	brne tim0_compar_exit
	rcall ENABLE_INT0_FALLING_EDGE
	clr counterToInt0Enable
	
tim0_compar_exit:
	reti

	

; interrupt on TIM1: pseudorandom delay
TIM1_COMPAR:
	tst tickCount
	breq counting_milliseconds

pseudo_delay:
	rcall CLEAR_TIMER1_COUNTER
	dec tickCount
	breq end_of_pseudo_delay
	reti

end_of_pseudo_delay:
	rcall SETUP_TIMER1_CTC_1_1
	; counting for 1 ms on prescaler 1/1 and freq 8 MHz
	SETUP_TIMER1_COMPARE temp, temp2, 8200	
	rcall ENABLE_INT0_FALLING_EDGE
	rcall LIGHT_ON_LED_PORTD0
	reti

counting_milliseconds:
	inc millisec
	cpi millisec, 10
	brne tim1_compar_exit

	clr millisec
	inc tensMilisec

	cpi tensMilisec, 10
	brne tim1_compar_exit

	clr tensMilisec
	inc hundredsMillisec

	cpi hundredsMillisec, 10
	brne tim1_compar_exit

	clr hundredsMillisec
	inc seconds
	
tim1_compar_exit:
	reti



; interrup on pushing button
INT0_INT:
	inc debugInt0Counter
	rcall DISABLE_INT0
	brts refresh_segment_digits

	in temp, TCNT1L

compare_with_40:
	; take 6-bit value of TCNT1L (simulate random value from 15 to 40)
	andi temp, 0x3f		
	cpi temp, 40
	brlo compare_with_15
	subi temp, 24

compare_with_15:
	cpi temp, 15
	brsh timer_setup_for_delay
	ldi temp2, 24
	add temp, temp2

timer_setup_for_delay:
	mov tickCount, temp
	; 3235 ticks on prescaler 1/256 - ~0.1 second, 
	; temp contain count of timer OCIE1A interrupts (temp * 0.1 - time to led on in seconds)
	SETUP_TIMER1_COMPARE temp, temp2, 3235		
	ENABLE_TIMER_INTERRUPT temp, OCIE1A 
	rcall CLEAR_TIMER1_COUNTER
	rcall CLEAR_DIGITS
	;set T bit for signaling that we do pseudo random delay
	set					
	reti

refresh_segment_digits:
	clt
	DISABLE_TIMER_INTERRUPT temp, OCIE1A
	rcall LIGHT_OFF_LED_PORTD0
	rcall SETUP_DIGITS
	rcall CLEAR_TIME_COUNTERS		
	rcall SETUP_TIMER1_CTC_1_256
	ldi temp, 0xFF
	out GIFR, temp
	reti



; On reset
START:
	; set up stack
	ldi temp, LOW(RAMEND)
	out SPL, temp

	rcall CLEAR_DIGITS

	; set up ports
	ser temp
	; all port B to out
	out DDRB, temp
	; bits 4-6 of port D to output, bit 2 - to input for interrupt from button, 
	; bit 0 to output for led	
	ldi temp, 0x71
	out DDRD, temp
	; led switch off			
	ldi temp, (OUT_TO_FIRST_DIG | 1 << PORTD2 | 1 << PORTD0) 
	out PORTD, temp

	; set up 8-bit timer for 7-segment indicator refresh
	; 180 interrapts/sec for prescaler 1/256 on 8 MHz
	ldi temp, TIMER0_COUNTER	
	out OCR0A, temp
	; CTC mode
	ldi temp, (1 << WGM01)		
	out TCCR0A, temp
	; prescaler 1/256
	ldi temp, (1 << CS02)		
	out TCCR0B, temp
	ENABLE_TIMER_INTERRUPT temp, OCIE0A

	; setupt 16 bit timer1			
	rcall SETUP_TIMER1_CTC_1_256
		
	clr debugInt0Counter
	clr debugDelayBits

	sei

INF_LOOP:
	rjmp INF_LOOP



ENABLE_INT0_FALLING_EDGE:
	in temp, MCUCR
	sbr temp, 0x03
	out MCUCR, temp

	ldi temp, 0xFF
	out GIFR, temp

	in temp, GIMSK
	; External Interrupt Request 0 Enable on PORTD2
	sbr temp, (1 << INT0)		
	out GIMSK, temp
	ret



DISABLE_INT0:
	in temp, GIMSK
	; External Interrupt Request 0 Enable on PORTD2
	cbr temp, (1 << INT0)		
	out GIMSK, temp
	ret



CLEAR_TIMER1_COUNTER:
	clr temp
	out TCNT1H, temp
	out TCNT1L, temp
	ret



; digits set to "zero" for 7segment indicator
CLEAR_DIGITS:
	clr temp
	UPDATE_DIGIT temp, digit1
	UPDATE_DIGIT temp, digit2
	UPDATE_DIGIT temp, digit3
	ret



SETUP_DIGITS:
	clr temp2
	cpi seconds, 101
	brlo calc_digits

	ldi temp, 0x0b
	UPDATE_DIGIT temp, digit1
	UPDATE_DIGIT temp, digit2
	UPDATE_DIGIT temp, digit3
	ret

calc_digits:
	cpi seconds, 100
	brne lower_then_100_seconds

	ldi millisec, 0
	ldi tensMilisec, 0
	ldi hundredsMillisec, 1

	clr temp2
	sbr temp2, (1 << NEED_DOT_ON_FIRST_DIGIT)
	rjmp update_digits

lower_then_100_seconds:
	cpi seconds, 10
	brlo lower_then_10_seconds
	clr temp

division_start:
	inc temp
	subi seconds, 10
	cpi seconds, 10
	brsh division_start

	mov millisec, hundredsMillisec
	mov tensMilisec, seconds
	mov hundredsMillisec, temp

	clr temp2
	sbr temp2, (1 << NEED_DOT_ON_SECOND_DIGIT)
	rjmp update_digits

lower_then_10_seconds:
	tst seconds
	breq update_digits
	mov millisec, tensMilisec
	mov tensMilisec, hundredsMillisec
	mov hundredsMillisec, seconds

	clr temp2
	sbr temp2, (1 << NEED_DOT_ON_THIRD_DIGIT)

update_digits:
	UPDATE_DIGIT millisec, digit1
	UPDATE_DIGIT tensMilisec, digit2
	UPDATE_DIGIT hundredsMillisec, digit3

	sbrc temp2, NEED_DOT_ON_FIRST_DIGIT
	ori digit1, DOT_MASK

	sbrc temp2, NEED_DOT_ON_SECOND_DIGIT
	ori digit2, DOT_MASK

	sbrc temp2, NEED_DOT_ON_THIRD_DIGIT
	ori digit3, DOT_MASK

	ret



CLEAR_TIME_COUNTERS:
	clr seconds
	clr hundredsMillisec
	clr tensMilisec
	clr millisec
	ret



SETUP_TIMER1_CTC_1_1:
	; prescaler 1/1
	ldi temp, (1 << WGM12 | 1 << CS10)		
	out TCCR1B, temp
	ret



SETUP_TIMER1_CTC_1_256:
	ldi temp, (1 << WGM12 | 1 << CS12)
	out TCCR1B, temp
	ret



LIGHT_ON_LED_PORTD0:
	in temp, PORTD
	cbr temp, 0x01
	out PORTD, temp
	ret



LIGHT_OFF_LED_PORTD0:
	in temp, PORTD
	sbr temp, 0x01
	out PORTD, temp
	ret



; bit masks for digits on 7-segment indicator
digitToMask:
.db 0b00111111, 0b00000110, 0b01011011, 0b01001111, 0b01100110, 0b01101101, 0b01111101, 0b00000111, 0b01111111, 0b01101111, 0b11111111, 0b11111111
