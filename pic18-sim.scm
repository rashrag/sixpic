;;; File: "pic18-sim.scm"

(include "pic18.scm")

;------------------------------------------------------------------------------

(define pic18-ram   #f)
(define pic18-rom   #f)
(define pic18-stack #f)
(define pic18-pc    #f)
(define pic18-wreg  #f)

(define pic18-carry-flag    #f)
(define pic18-deccarry-flag #f)
(define pic18-zero-flag     #f)
(define pic18-overflow-flag #f)
(define pic18-negative-flag #f)

(define pic18-cycles #f)
(define pic18-exit #f)

(define (get-ram adr)
  (cond ((= adr TOSU)
         (bitwise-and (arithmetic-shift (get-tos) -16) #xff))
        ((= adr TOSH)
         (bitwise-and (arithmetic-shift (get-tos) -8) #xff))
        ((= adr TOSL)
         (bitwise-and (get-tos) #xff))
        ((= adr PCL)
         (set-ram PCLATU (bitwise-and (arithmetic-shift (get-pc) -16)) #x1f)
         (set-ram PCLATH (bitwise-and (arithmetic-shift (get-pc) -8)) #xff)
         (bitwise-and (get-pc) #xfe))
        ((= adr STATUS)
         (+ pic18-carry-flag
            (arithmetic-shift pic18-deccarry-flag 1)
            (arithmetic-shift pic18-zero-flag 2)
            (arithmetic-shift pic18-overflow-flag 3)
            (arithmetic-shift pic18-negative-flag 4)))
	((assq adr (list (cons INDF0 (cons FSR0H FSR0L))
			 (cons INDF1 (cons FSR1H FSR1L))
			 (cons INDF2 (cons FSR2H FSR2L))))
	 => (lambda (x)
	      (get-ram (bitwise-ior
			(arithmetic-shift (u8vector-ref pic18-ram
							(cadr x))
					  8)
			(u8vector-ref pic18-ram
				      (cddr x))))))
	;; TODO pre/post inc/dec 0..2
        (else
         (u8vector-ref pic18-ram adr))))

(define (set-ram adr byte)
  (cond ((= adr TOSU)
         (set-tos (+ (bitwise-and (get-tos) #x00ffff)
                     (arithmetic-shift (bitwise-and byte #x1f) 16))))
        ((= adr TOSH)
         (set-tos (+ (bitwise-and (get-tos) #x1f00ff)
                     (arithmetic-shift byte 8))))
        ((= adr TOSL)
         (set-tos (+ (bitwise-and (get-tos) #x1fff00)
                     byte)))
        ((= adr PCL)
         (set-pc (+ (bitwise-and (arithmetic-shift (get-ram PCLATU) 16) #x1f)
                    (bitwise-and (arithmetic-shift (get-ram PCLATH) 8) #xff)
                    (bitwise-and byte #xfe))))
        ((= adr STATUS)
         (set! pic18-carry-flag    (bitwise-and byte 1))
         (set! pic18-deccarry-flag (arithmetic-shift (bitwise-and byte 2) -1))
         (set! pic18-zero-flag     (arithmetic-shift (bitwise-and byte 4) -2))
         (set! pic18-overflow-flag (arithmetic-shift (bitwise-and byte 8) -3))
         (set! pic18-negative-flag (arithmetic-shift (bitwise-and byte 16) -4)))
	((assq adr (list (cons INDF0 (cons FSR0H FSR0L))
			 (cons INDF1 (cons FSR1H FSR1L))
			 (cons INDF2 (cons FSR2H FSR2L))))
	 => (lambda (x)
	      (set-ram (bitwise-ior ;; TODO factor common code with get-ram ?
			(arithmetic-shift (u8vector-ref pic18-ram
							(cadr x))
					  8)
			(u8vector-ref pic18-ram
				      (cddr x)))
		       byte)))
	;; TODO all other special array registers
        (else
         (u8vector-set! pic18-ram adr byte))))

(define (get-rom adr)
  (u8vector-ref pic18-rom adr))

(define (set-rom adr byte)
  (u8vector-set! pic18-rom adr byte))

(define (get-stack adr)
  (vector-ref pic18-stack adr))

(define (set-stack adr pc)
  (vector-set! pic18-stack adr pc))

(define (get-pc)
  pic18-pc)

(define (set-pc pc)
  (set! pic18-pc pc))

(define (get-sp)
  (bitwise-and (get-ram STKPTR) #x1f))

(define (set-sp sp)
  (set-ram STKPTR
           (bitwise-ior sp
                        (bitwise-and (get-ram STKPTR) #xe0))))

(define (get-tos)
  (vector-ref pic18-stack (- (get-sp) 1)))

(define (set-tos pc)
  (vector-set! pic18-stack (- (get-sp) 1) pc))

(define (stack-push pc)
  (set-sp (+ (get-sp) 1))
  (set-tos pc))

(define (stack-pop)
  (set-pc (get-tos))
  (set-sp (- (get-sp) 1)))

(define (get-bsr)
  (bitwise-and (get-ram BSR) #x0f))

(define (get-wreg)
  pic18-wreg)

(define (set-wreg byte)
  (set! pic18-wreg byte))

(define (zero-flag?)
  (not (= 0 pic18-zero-flag)))

(define (set-zero-flag flag)
  (set! pic18-zero-flag flag))

(define (negative-flag?)
  (not (= 0 pic18-negative-flag)))

(define (set-negative-flag flag)
  (set! pic18-negative-flag flag))

(define (carry-flag?)
  (not (= 0 pic18-carry-flag)))

(define (set-carry-flag flag)
  (set! pic18-carry-flag flag))

(define (deccarry-flag?)
  (not (= 0 pic18-deccarry-flag)))

(define (set-deccarry-flag flag)
  (set! pic18-deccarry-flag flag))

(define (overflow-flag?)
  (not (= 0 pic18-overflow-flag)))

(define (set-overflow-flag flag)
  (set! pic18-overflow-flag flag))

(define (pic18-sim-setup)
  (set! pic18-ram   (make-u8vector #x1000 0))
  (set! pic18-rom   (make-u8vector #x2000 0))
  (set! pic18-stack (make-vector #x1f 0))
  (set-pc 0)
  (set-wreg 0)
  (set! pic18-carry-flag    0)
  (set! pic18-deccarry-flag 0)
  (set! pic18-zero-flag     0)
  (set! pic18-overflow-flag 0)
  (set! pic18-negative-flag 0))

(define (pic18-sim-cleanup)
  (set! pic18-ram   #f)
  (set! pic18-rom   #f)
  (set! pic18-stack #f))

;------------------------------------------------------------------------------

(define (last-pc)
  (let ((pc (- (get-pc) 2)))
    (list (get-sp) " " (- pic18-cycles 1) " "
          (substring (number->string (+ #x1000000 pc) 16) 1 7)
          "	")))

(define (illegal-opcode opcode)
  (if trace-instr
      (display (list (last-pc) "	*illegal*")))
  (error "illegal opcode" opcode))

(define decode-vector
  (make-vector 256 illegal-opcode))

(define (decode-opcode opcode-bits shift action)
  (if (< shift 8)
      (error "shift=" shift))
  (let ((n (arithmetic-shift 1 (- shift 8)))
        (base (arithmetic-shift opcode-bits (- shift 8))))
    (let loop ((i 0))
      (if (< i n)
          (begin
            (vector-set! decode-vector (+ base i) action)
            (loop (+ i 1)))))))

(define (byte-oriented opcode mnemonic flags-changed operation)
  (byte-oriented-aux opcode mnemonic flags-changed operation 'wreg))
(define (byte-oriented-file opcode mnemonic flags-changed operation)
  (byte-oriented-aux opcode mnemonic flags-changed operation 'file))
(define (byte-oriented-wide opcode mnemonic flags-changed operation dest)
  ;; for use with instructions that have results more than a byte wide, such
  ;; as multiplication. the result goes at the given addresses
  (byte-oriented-aux opcode mnemonic flags-changed operation dest)) ;; TODO do the same for literals

(define (byte-oriented-aux opcode mnemonic flags-changed operation dest)
  (let* ((f (bitwise-and opcode #xff))
         (adr (if (= 0 (bitwise-and opcode #x100))
                  (if (= 0 (bitwise-and f #x80)) f (+ f #xf00))
                  (+ f (arithmetic-shift (get-bsr) 8)))))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       (let ((x (assv adr file-reg-names)))
                         (if x (cdr x) (list "0x" (number->string adr 16))))
                       (if (or (eq? dest 'wreg)
			       (= 0 (bitwise-and opcode #x200)))
                           ", w"
                           "")
                       "")))
    (let* ((result (operation (get-ram adr)))
           (result-8bit (bitwise-and result #xff)))
      (cond ((list? dest)
	     ;; result is more than a byte wide (i.e. multiplication)
	     ;; put it in the right destinations (dest is a list of addresses)
	     (let loop ((dest dest) (result result))
	       (if (not (null? dest))
		   ;; the head of the list is the lsb
		   (begin (set-ram (car dest) (bitwise-and result #xff))
			  (loop (cdr dest) (arithmetic-shift result -8))))))
	    ((or (eq? dest 'file) (not (= 0 (bitwise-and opcode #x200))))
	     ;; the result goes in memory (file)
	     (set-ram adr result-8bit))
	    ((eq? dest 'wreg)
	     ;; result goes in wreg
	     (set-wreg result-8bit)))
      (if (not (eq? flags-changed 'none))
          (begin
            (set-zero-flag (if (= 0 result-8bit) 1 0))
            (if (not (eq? flags-changed 'z))
                (begin
                  (set-negative-flag (if (> result-8bit #x7f) 1 0))
                  (if (not (eq? flags-changed 'z-n))
                      (begin
                        (set-carry-flag (if (or (> result #xff)
						(< result 0))
					    1 0))
                        (if (not (eq? flags-changed 'c-z-n))
                            (begin
                              (set-deccarry-flag 0);;;;;;;;;;;;;;
                              (set-overflow-flag 0))))))))))));;;;;;;;;;;;;;

(define (bit-oriented opcode mnemonic operation)
  (let* ((f (bitwise-and opcode #xff))
         (adr (if (= 0 (bitwise-and opcode #x100))
                  (if (= 0 (bitwise-and f #x80)) f (+ f #xf00))
                  (+ f (arithmetic-shift (get-bsr) 8))))
         (b (bitwise-and (arithmetic-shift opcode -9) 7)))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       (let ((x (assv adr file-reg-names)))
                         (if x (cdr x) (list "0x" (number->string adr 16))))
                       ", "
                       (if (= adr STATUS)
                           (cdr (assv b '((0 . C)
                                          (1 . DC)
                                          (2 . Z)
                                          (3 . OV)
                                          (4 . N)
                                          (5 . 5)
                                          (6 . 6)
                                          (7 . 7))))
                           b)
                       "")))
    (let* ((result (operation (get-ram adr) b))
           (result-8bit (bitwise-and result #xff)))
      (set-ram adr result-8bit))))

(define (short-relative-branch opcode mnemonic branch)
  (let* ((n (bitwise-and opcode #xff))
         (adr (+ (get-pc) (* 2 (if (> n #x7f) (- n #x100) n)))))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       "0x"
                       (number->string adr 16)
                       "")))
    (if (branch)
        (begin
          (get-program-mem)
          (set-pc adr)))))

(define (long-relative-branch opcode mnemonic call?)
  (let* ((n (bitwise-and opcode #x7ff))
         (adr (+ (get-pc) (* 2 (if (> n #x3ff) (- n #x800) n)))))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       "0x"
                       (number->string adr 16)
                       "")))
    (if call?
        (stack-push (get-pc)))
    (get-program-mem)
    (set-pc adr)))

(define (call-branch opcode mnemonic)
  (let ((adr (* 2 (+ (bitwise-and opcode #xff)
                     (arithmetic-shift (get-program-mem) 8)))))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       "0x"
                       (number->string adr 16)
                       (if (= 0 (bitwise-and opcode #x100))
                           ""
                           ", FAST")
                       "")))
    (stack-push (get-pc))
    (if (not (= 0 (bitwise-and opcode #x100)))
        (error "call fast not implemented"))
    (set-pc adr)))

(define (goto-branch opcode mnemonic)
  (let ((adr (* 2 (+ (bitwise-and opcode #xff)
                     (arithmetic-shift (get-program-mem) 8)))))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       "0x"
                       (number->string adr 16)
                       "")))
    (set-pc adr)))

(define (literal-operation opcode mnemonic flags-changed operation)
  (let ((k (bitwise-and opcode #xff)))
    (if trace-instr
        (display (list (last-pc) "	" mnemonic "	"
                       (if (< k 10) k (list "0x" (number->string k 16)))
                       "")))
    (let* ((result (operation k))
           (result-8bit (bitwise-and result #xff)))
      (set-wreg result-8bit)
      (if (not (eq? flags-changed 'none))
          (begin
            (set-zero-flag (if (= 0 result-8bit) 1 0))
            (if (not (eq? flags-changed 'z))
                (begin
                  (set-negative-flag (if (> result-8bit #x7f) 1 0))
                  (if (not (eq? flags-changed 'z-n))
                      (begin
                        (set-carry-flag (if (> result #xff) 1 0))
                        (if (not (eq? flags-changed 'c-z-n))
                            (begin
                              (set-deccarry-flag 0);;;;;;;;;;;;;;
                              (set-overflow-flag 0))))))))))));;;;;;;;;;;;;;

(define (get-program-mem)
  (set! pic18-cycles (+ pic18-cycles 1))
  (let* ((pc (get-pc))
         (lsb (get-rom pc))
         (msb (get-rom (+ pc 1))))
    (set-pc (+ (get-pc) 2))
    (+ (arithmetic-shift msb 8) lsb)))

(define (skip)
  (get-program-mem))

(define (hex n)
  (substring (number->string (+ #x100 n) 16) 1 3))

(define (dump-mem)

  (display "	")
  (let loop ((i 0))
    (if (< i 10)
        (begin
          (display (list (hex (u8vector-ref pic18-ram i)) " "))
          (loop (+ i 1)))))
  (display (list "  WREG=" (hex (get-wreg)) "\n")))

(define (pic18-execute)
  (set! pic18-exit #f)
  (set! pic18-cycles 0)
  (if trace-instr
      (display "				"))
  (let loop ()
    (if trace-instr
        (dump-mem))
    (if pic18-exit
        (begin
          (display (list "WREG = d'" (get-wreg) "'\n")))
        (let ((opcode (get-program-mem)))
          (let ((proc (vector-ref decode-vector (arithmetic-shift opcode -8))))
            (proc opcode)
            (loop))))))

(define trace-instr #t)

(define (carry)
  (if (> pic18-carry-flag 0)
      (begin (set! pic18-carry-flag #f) ;; TODO is this how the PIC18 hardware does it ?
	     1)
      0))

;------------------------------------------------------------------------------

; Byte-oriented file register operations.

(decode-opcode #b001001 10
  (lambda (opcode)
    (byte-oriented opcode "addwf" 'c-dc-z-ov-n
     (lambda (f)
       (+ f (get-wreg))))))

(decode-opcode #b001000 10
  (lambda (opcode)
    (byte-oriented opcode "addwfc" 'c-dc-z-ov-n
     (lambda (f)
       (+ f (get-wreg) (carry))))))

(decode-opcode #b000101 10
  (lambda (opcode)
    (byte-oriented opcode "andwf" 'z-n
     (lambda (f)
       (bitwise-and f (get-wreg))))))

(decode-opcode #b0110101 9
  (lambda (opcode)
    (byte-oriented-file opcode "clrf" 'z
     (lambda (f)
       0))))

(decode-opcode #b000111 10
  (lambda (opcode)
    (byte-oriented opcode "comf" 'z-n
     (lambda (f)
       (bitwise-not f)))))

(decode-opcode #b0110001 9
  (lambda (opcode)
    (byte-oriented-file opcode "cpfseq" 'none
     (lambda (f)
       (if (= f (get-wreg)) (skip))
       f))))

(decode-opcode #b0110010 9
  (lambda (opcode)
    (byte-oriented-file opcode "cpfsgt" 'none
     (lambda (f)
       (if (> f (get-wreg)) (skip))
       f))))

(decode-opcode #b0110000 9
  (lambda (opcode)
    (byte-oriented-file opcode "cpfslt" 'none
     (lambda (f)
       (if (< f (get-wreg)) (skip))
       f))))

(decode-opcode #b000001 10
  (lambda (opcode)
    (byte-oriented opcode "decf" 'c-dc-z-ov-n
     (lambda (f)
       (- f 1)))))

(decode-opcode #b001011 10
  (lambda (opcode)
    (byte-oriented opcode "decfsz" 'none
     (lambda (f)
       (if (= f 1) (skip))
       (- f 1)))))

(decode-opcode #b010011 10
  (lambda (opcode)
    (byte-oriented opcode "dcfsnz" 'none
     (lambda (f)
       (if (not (= f 1)) (skip))
       (- f 1)))))

(decode-opcode #b001010 10
  (lambda (opcode)
    (byte-oriented opcode "incf" 'c-dc-z-ov-n
     (lambda (f)
       (+ f 1)))))

(decode-opcode #b001111 10
  (lambda (opcode)
    (byte-oriented opcode "incfsz" 'none
     (lambda (f)
       (if (= f #xff) (skip))
       (+ f 1)))))

(decode-opcode #b010010 10
  (lambda (opcode)
    (byte-oriented opcode "infsnz" 'none
     (lambda (f)
       (if (not (= f #xff)) (skip))
       (+ f 1)))))

(decode-opcode #b000100 10
  (lambda (opcode)
    (byte-oriented opcode "iorwf" 'z-n
     (lambda (f)
       (bitwise-ior f (get-wreg))))))

(decode-opcode #b010100 10
  (lambda (opcode)
    (byte-oriented opcode "movf" 'z-n
     (lambda (f)
       f))))

(decode-opcode #b1100 12
  (lambda (opcode)
    '(byte-to-byte "movff")
    (byte-oriented opcode "movff" 'none
      (lambda (f)
	f)))) ;; TODO doesn't work

(decode-opcode #b0110111 9
  (lambda (opcode)
    (byte-oriented-file opcode "movwf" 'none
     (lambda (f)
       (get-wreg)))))

(decode-opcode #b0000001 9
  (lambda (opcode)
    (byte-oriented-wide opcode "mulwf" 'none
     (lambda (f)
       (* f (get-wreg)))
     (list PRODL PRODH))))

(decode-opcode #b0110110 9
  (lambda (opcode)
    (byte-oriented-file opcode "negf" 'c-dc-z-ov-n
     (lambda (f)
       (- f)))))

(decode-opcode #b001101 10
  (lambda (opcode)
    (byte-oriented opcode "rlcf" 'c-z-n
     (lambda (f)
       (+ (arithmetic-shift f 1) (carry))))))

(decode-opcode #b010001 10
  (lambda (opcode)
    (byte-oriented opcode "rlncf" 'z-n
     (lambda (f)
       (+ (arithmetic-shift f 1) (arithmetic-shift f -7))))))

(decode-opcode #b001100 10
  (lambda (opcode)
    (byte-oriented opcode "rrcf" 'c-z-n
     (lambda (f)
       (+ (arithmetic-shift f -1) (arithmetic-shift (carry) 7))))))

(decode-opcode #b010000 10
  (lambda (opcode)
    (byte-oriented opcode "rrncf" 'z-n
     (lambda (f)
       (+ (arithmetic-shift f -1) (arithmetic-shift f 7))))))

(decode-opcode #b0110100 9
  (lambda (opcode)
    (byte-oriented-file opcode "setf" 'z
     (lambda (f)
       #xff))))

(decode-opcode #b010101 10
  (lambda (opcode)
    (byte-oriented opcode "subfwb" 'c-dc-z-ov-n
     (lambda (f)
       (- (get-wreg) f (carry)))))) ;; TODO was (- 1 (carry)), but caused problems with the other

(decode-opcode #b010111 10
  (lambda (opcode)
    (byte-oriented opcode "subwf" 'c-dc-z-ov-n
     (lambda (f)
       (- f (get-wreg))))))

(decode-opcode #b010110 10
  (lambda (opcode)
    (byte-oriented opcode "subwfb" 'c-dc-z-ov-n
     (lambda (f)
       (- f (get-wreg) (carry)))))) ;; TODO !carry didn't work

(decode-opcode #b001110 10
  (lambda (opcode)
    (byte-oriented opcode "swapf" 'none
     (lambda (f)
       (+ (arithmetic-shift f -4) (arithmetic-shift f 4))))))

(decode-opcode #b0110011 9
  (lambda (opcode)
    (byte-oriented-file opcode "tstfsz" 'none
     (lambda (f)
       (if (= f 0) (skip))))))

(decode-opcode #b000110 10
  (lambda (opcode)
    (byte-oriented opcode "xorwf" 'z-n
     (lambda (f)
       (bitwise-xor f (get-wreg))))))

; Bit-oriented file register operations.

(decode-opcode #b1001 12
  (lambda (opcode)
    (bit-oriented opcode "bcf"
     (lambda (f b)
       (bitwise-and f (bitwise-not (arithmetic-shift 1 b)))))))

(decode-opcode #b1000 12
  (lambda (opcode)
    (bit-oriented opcode "bsf"
     (lambda (f b)
       (bitwise-ior f (arithmetic-shift 1 b))))))

(decode-opcode #b1011 12
  (lambda (opcode)
    (bit-oriented opcode "btfsc"
     (lambda (f b)
       (if (= 0 (bitwise-and f (arithmetic-shift 1 b))) (skip))
       f))))

(decode-opcode #b1010 12
  (lambda (opcode)
    (bit-oriented opcode "btfss"
     (lambda (f b)
       (if (not (= 0 (bitwise-and f (arithmetic-shift 1 b)))) (skip))
       f))))

(decode-opcode #b0111 12
  (lambda (opcode)
    (bit-oriented opcode "btg"
     (lambda (f b)
       (bitwise-xor f (arithmetic-shift 1 b))))))

; Control operations.

(decode-opcode #b11100010 8
  (lambda (opcode)
    (short-relative-branch opcode "bc"
     (lambda ()
       (not (= 0 (carry)))))))

(decode-opcode #b11100110 8
  (lambda (opcode)
    (short-relative-branch opcode "bn"
     (lambda ()
       (not (= 0 (negative)))))))

(decode-opcode #b11100011 8
  (lambda (opcode)
    (short-relative-branch opcode "bnc"
     (lambda ()
       (= 0 (carry))))))

(decode-opcode #b11100111 8
  (lambda (opcode)
    (short-relative-branch opcode "bnn"
     (lambda ()
       (= 0 (negative))))))

(decode-opcode #b11100101 8
  (lambda (opcode)
    (short-relative-branch opcode "bnov"
     (lambda ()
       (= 0 (overflow))))))

(decode-opcode #b11100001 8
  (lambda (opcode)
    (short-relative-branch opcode "bnz"
     (lambda ()
       (= 0 (zero))))))

(decode-opcode #b11100100 8
  (lambda (opcode)
    (short-relative-branch opcode "bov"
     (lambda ()
       (not (= 0 (overflow)))))))

(decode-opcode #b11010 11
  (lambda (opcode)
    (long-relative-branch opcode "bra" #f)))

(decode-opcode #b11100000 8
  (lambda (opcode)
    (short-relative-branch opcode "bz"
     (lambda ()
       (not (= 0 (zero)))))))

(decode-opcode #b1110110 9
  (lambda (opcode)
    (call-branch opcode "call")))

(decode-opcode #b11101111 8
  (lambda (opcode)
    (goto-branch opcode "goto")))

(decode-opcode #b11011 11
  (lambda (opcode)
    (long-relative-branch opcode "rcall" #t)))

(decode-opcode #b1111 12
  (lambda (opcode)
    (if trace-instr
        (display (list (last-pc) "	nop	")))))

(decode-opcode #b00000000 8
  (lambda (opcode)
    (cond ((= opcode #b0000000000000100)
           (if trace-instr
               (display (list (last-pc) "	clrwdt	")))
           (clrwdt opcode))
          ((= opcode #b0000000000000111)
           (if trace-instr
               (display (list (last-pc) "	daw	")))
           (daw opcode))
          ((= opcode #b0000000000000000)
           (if trace-instr
               (display (list (last-pc) "	nop	"))))
          ((= opcode #b0000000000000110)
           (if trace-instr
               (display (list (last-pc) "	pop	")))
           (stack-pop))
          ((= opcode #b0000000000000101)
           (if trace-instr
               (display (list (last-pc) "	push	")))
           (stack-push (get-pc)))
          ((= opcode #b0000000011111111)
           (if trace-instr
               (display (list (last-pc) "	reset	")))
           (set-pc 0))
          ((= opcode #b0000000000010000)
           (if trace-instr
               (display (list (last-pc) "	retfie	")))
           (get-program-mem)
           (stack-pop))
          ((= opcode #b0000000000010001)
           (if trace-instr
               (display (list (last-pc) "	retfie	FAST")))
           (error "retfie fast not implemented")
           (get-program-mem)
           (stack-pop))
          ((= opcode #b0000000000010010)
           (if trace-instr
               (display (list (last-pc) "	return	")))
           (get-program-mem)
           (stack-pop))
          ((= opcode #b0000000000010011)
           (if trace-instr
               (display (list (last-pc) "	return	FAST")))
           (error "return fast not implemented")
           (get-program-mem)
           (stack-pop))
          ((= opcode #b0000000000000011)
           (if trace-instr
               (display (list (last-pc) "	sleep	")))
           (set! pic18-exit #t))
          (else
           (if trace-instr
               (display (list (last-pc) "	???	")))
           (error "???")))))

; Literal operations.

(decode-opcode #b00001111 8
  (lambda (opcode)
    (literal-operation opcode "addlw" 'c-dc-z-ov-n
     (lambda (k)
       (+ k (get-wreg))))))

(decode-opcode #b00001011 8
  (lambda (opcode)
    (literal-operation opcode "andlw" 'z-n
     (lambda (k)
       (bitwise-and k (get-wreg))))))

(decode-opcode #b00001001 8
  (lambda (opcode)
    (literal-operation opcode "iorlw" 'z-n
     (lambda (k)
       (bitwise-ior k (get-wreg))))))

'
(define (lfsr f k)
  (make-instruction
   2
   (lambda ()
     (make-listing "lfsr" (file-text f) (lit-text k)))
   (lambda ()
     (asm-16 (bitmask "1110 1110 00ff kkkk" (file f) (quotient (lit k) 256)))
     (asm-16 (bitmask "1111 0000 kkkk kkkk" (modulo (lit k) 256))))))

'
(define (movlb k)
  (make-instruction
   1
   (lambda ()
     (make-listing "movlb" (lit-text k)))
   (lambda ()
     (asm-16 (bitmask "0000 0001 0000 kkkk" (lit k))))))

(decode-opcode #b00001110 8
  (lambda (opcode)
    (literal-operation opcode "movlw" 'none
     (lambda (k)
       k))))

(decode-opcode #b00001101 8
  (lambda (opcode)
    (literal-operation opcode "mullw" 'none
     (lambda (k)
       (* k (get-wreg))))))

(decode-opcode #b00001100 8
  (lambda (opcode)
    (literal-operation opcode "retlw" 'none
     (lambda (k)
       (get-program-mem)
       (stack-pop)
       k))))

(decode-opcode #b00001000 8
  (lambda (opcode)
    (literal-operation opcode "sublw" 'c-dc-z-ov-n
     (lambda (k)
       (- k (get-wreg))))))

(decode-opcode #b00001010 8
  (lambda (opcode)
    (literal-operation opcode "xorlw" 'z-n
     (lambda (k)
       (bitwise-xor k (get-wreg))))))

; Program memory operations.

'
(define (tblrd*)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblrd*"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1000")))))

'
(define (tblrd*+)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblrd*+"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1001")))))

'
(define (tblrd*-)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblrd*-"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1010")))))

'
(define (tblrd+*)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblrd+*"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1011")))))

'
(define (tblwt*)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblwt*"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1100")))))

'
(define (tblwt*+)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblwt*+"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1101")))))

'
(define (tblwt*-)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblwt*-"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1110")))))

'
(define (tblwt+*)
  (make-instruction
   2
   (lambda ()
     (make-listing "tblwt+*"))
   (lambda ()
     (asm-16 (bitmask "0000 0000 0000 1111")))))

;------------------------------------------------------------------------------

(define (read-hex-file filename)

  (define addr-width 32)

  (define (syntax-error)
    (error "*** Syntax error in HEX file"))

  (let ((f
         (with-exception-catcher
          (lambda (exc)
            #f)
          (lambda ()
            (open-input-file filename)))))

    (define mem (make-vector 16 #f))

    (define (mem-store! a b)
      (let loop ((m mem)
                 (a a)
                 (x (- addr-width 4)))
        (if (= x 0)
            (vector-set! m a b)
            (let ((i (arithmetic-shift a (- x))))
              (let ((v (vector-ref m i)))
                (loop (or v
                          (let ((v (make-vector 16 #f)))
                            (vector-set! m i v)
                            v))
                      (- a (arithmetic-shift i x))
                      (- x 4)))))))

    (define (mem->list)

      (define (f m a n tail)

        (define (g i a n tail)
          (if (>= i 0)
              (g (- i 1) (- a n) n (f (vector-ref m i) a n tail))
              tail))

        (if m
            (if (= n 1)
                (cons (cons (- a 1) m) tail)
                (g 15 a (quotient n 16) tail))
            tail))

      (f mem (expt 2 addr-width) (expt 2 addr-width) '()))

    (define hi16
      0)

    (define (read-hex-nibble)
      (let ((c (read-char f)))
        (cond ((and (char>=? c #\0) (char<=? c #\9))
               (- (char->integer c) (char->integer #\0)))
              ((and (char>=? c #\A) (char<=? c #\F))
               (+ 10 (- (char->integer c) (char->integer #\A))))
              ((and (char>=? c #\a) (char<=? c #\f))
               (+ 10 (- (char->integer c) (char->integer #\a))))
              (else
               (syntax-error)))))
             
    (define (read-hex-byte)
      (let* ((a (read-hex-nibble))
             (b (read-hex-nibble)))
        (+ b (* a 16))))

    (if f
        (begin
          (let loop1 ()
            (let ((c (read-char f)))
              (cond ((not (char? c)))
                    ((or (char=? c #\linefeed)
                         (char=? c #\return))
                     (loop1))
                    ((not (char=? c #\:))
                     (syntax-error))
                    (else
                     (let* ((len (read-hex-byte))
                            (a1 (read-hex-byte))
                            (a2 (read-hex-byte))
                            (type (read-hex-byte)))
                       (let* ((adr (+ a2 (* 256 a1)))
                              (sum (+ len a1 a2 type)))
                         (cond ((= type 0)
                                (let loop2 ((i 0))
                                  (if (< i len)
                                      (let ((a (+ adr (* hi16 65536)))
                                            (b (read-hex-byte)))
                                        (mem-store! a b)
                                        (set! adr (modulo (+ adr 1) 65536))
                                        (set! sum (+ sum b))
                                        (loop2 (+ i 1))))))
                               ((= type 1)
                                (if (not (= len 0))
                                    (syntax-error)))
                               ((= type 4)
                                (if (not (= len 2))
                                    (syntax-error))
                                (let* ((a1 (read-hex-byte))
                                       (a2 (read-hex-byte)))
                                  (set! sum (+ sum a1 a2))
                                  (set! hi16 (+ a2 (* 256 a1)))))
                               (else
                                (syntax-error)))
                         (let ((check (read-hex-byte)))
                           (if (not (= (modulo (- sum) 256) check))
                               (syntax-error)))
                         (let ((c (read-char f)))
                           (if (or (not (or (char=? c #\linefeed)
                                            (char=? c #\return)))
                                   (not (= type 1)))
                               (loop1)))))))))

          (close-input-port f)

          (mem->list))
        (begin
          (error "*** Could not open the HEX file")
          #f))))

;------------------------------------------------------------------------------

(define (execute-hex-file filename)
  (let ((program (read-hex-file filename)))
    (pic18-sim-setup)
    (for-each (lambda (x) (set-rom (car x) (cdr x))) program)
    (pic18-execute)
    (pic18-sim-cleanup)))
