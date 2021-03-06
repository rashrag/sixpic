(define bank-1-used? #f)

(define (linearize-and-cleanup cfg)

  (define bbs-vector (cfg->vector cfg))

  (define todo '())

  (define (add-todo bb)
    (set! todo (cons bb todo)))

  (define rev-code '())

  (define (emit instr)
    (set! rev-code (cons instr rev-code)))

  (define (outside-bank-0? adr)
    (if (and (> adr #x5F) (< adr #xF60)) ; not a special register
	(begin (set! bank-1-used? #t) #t)
	#f))
  (define (emit-byte-oriented op file #!optional (d? #t) (w? #f))
    ;; we might have to access the second bank
    (emit (if (outside-bank-0? file)
	      (if d?
		  (list op (- file 96) (if w? 'w 'f) 'b)
		  (list op (- file 96) 'b))
	      (if d?
		  (list op file (if w? 'w 'f) 'a)
		  (list op file 'a)))))
  (define (emit-bit-oriented op file bit)
    (emit (if (outside-bank-0? file)
	      (list op (- file 96) bit 'b)
	      (list op file        bit 'a))))

  (define (movlw val)
    (emit (list 'movlw val)))
  (define (movwf adr)
    (emit-byte-oriented 'movwf adr #f))
  (define (movfw adr)
    (emit-byte-oriented 'movf adr #t #t))
  (define (movff src dst)
    ;; anything over #x5f is in the second bank (at #x100)
    (let ((src (if (outside-bank-0? src)
		   (+ src #xa0)
		   src))
	  (dst (if (outside-bank-0? dst)
		   (+ dst #xa0)
		   dst)))
      (emit (list 'movff src dst))))

  (define (clrf adr)
    (emit-byte-oriented 'clrf adr #f))
  (define (setf adr)
    (emit-byte-oriented 'setf adr #f))

  (define (incf adr)
    (emit-byte-oriented 'incf adr))
  (define (decf adr)
    (emit-byte-oriented 'decf adr))

  (define (addwf adr)
    (emit-byte-oriented 'addwf adr))
  (define (addwfc adr)
    (emit-byte-oriented 'addwfc adr))

  (define (subwf adr)
    (emit-byte-oriented 'subwf adr))
  (define (subwfb adr)
    (emit-byte-oriented 'subwfb adr))

  (define (mullw adr)
    (emit (list 'mullw adr)))
  (define (mulwf adr)
    (emit-byte-oriented 'mulwf adr #f))

  (define (andwf adr)
    (emit-byte-oriented 'andwf adr))
  (define (iorwf adr)
    (emit-byte-oriented 'iorwf adr))
  (define (xorwf adr)
    (emit-byte-oriented 'xorwf adr))

  (define (rlcf adr)
    (emit-byte-oriented 'rlcf adr))
  (define (rrcf adr)
    (emit-byte-oriented 'rrcf adr))

  (define (bcf adr bit)
    (emit-bit-oriented 'bcf adr bit))
  (define (bsf adr bit)
    (emit-bit-oriented 'bsf adr bit))
  (define (btg adr bit)
    (emit-bit-oriented 'btg adr bit))

  (define (comf adr)
    (emit-byte-oriented 'comf adr))

  (define (tblrd) ;; TODO support the different modes
    (emit (list 'tblrd)))
  
  (define (cpfseq adr)
    (emit-byte-oriented 'cpfseq adr #f))
  (define (cpfslt adr)
    (emit-byte-oriented 'cpfslt adr #f))
  (define (cpfsgt adr)
    (emit-byte-oriented 'cpfsgt adr #f))

  (define (bc label)
    (emit (list 'bc label)))
  (define (bra-or-goto label)
    (emit (list 'bra-or-goto label)))
  (define (goto label)
    (emit (list 'goto label)))

  (define (rcall label)
    (emit (list 'rcall label)))

  (define (return)
    (if (and #f (and (not (null? rev-code))
                     (eq? (caar rev-code) 'rcall)))
        (let ((label (cadar rev-code)))
          (set! rev-code (cdr rev-code))
          (bra-or-goto label))
        (emit (list 'return))))

  (define (label lab)
    (if (and (and (not (null? rev-code)) ;; TODO have a flag to disable this optimization
		  (or (eq? (caar rev-code) 'bra-or-goto)
		      (eq? (caar rev-code) 'goto))
		  (eq? (cadar rev-code) lab)))
        (begin
          (set! rev-code (cdr rev-code))
          (label lab))
        (emit (list 'label lab))))

  (define (sleep)
    (emit (list 'sleep)))

  (define (move-reg src dst)
    (cond ((= src dst))
          ((= src WREG)
           (movwf dst))
          ((= dst WREG)
           (movfw src))
          (else
           ;;         (movfw src)
           ;;         (movwf dst)
           ;; takes 2 cycles (as much as movfw src ; movwf dst), but takes
           ;; only 1 instruction
           (movff src dst))))

  (define (bb-linearize bb)
    (let ((label-num (bb-label-num bb)))
      (let ((bb (vector-ref bbs-vector label-num)))

        (define (move-lit n adr)
          (cond ((= n 0)
                 (clrf adr))
                ((= n #xff)
                 (setf adr))
                (else
                 (movlw n)
                 (movwf adr))))

	;; when eliminating additions/substractions, it is important that the
	;; next one ignores the carry/borrow, to avoid using a leftover carry
	;; from an earlier operation
	(define ignore-carry-borrow? #f)

	(define (dump-instr instr)
          (cond ((call-instr? instr)
                 (let* ((def-proc (call-instr-def-proc instr))
                        (entry (def-procedure-entry def-proc)))
                   (if (bb? entry)
                       (begin
                         (add-todo entry)
                         (let ((label (bb-label entry)))
                           (rcall label)))
                       (rcall entry))))
                ((return-instr? instr)
                 (return))
                (else
                 (let ((src1 (instr-src1 instr))
                       (src2 (instr-src2 instr))
                       (dst  (instr-dst  instr))
		       (id   (instr-id   instr)))
                   (if (and (or (not (byte-cell? dst))
                                (and (byte-cell-adr dst)
				     ;; must go in a special register, or in a
				     ;; live variable, or else don't generate
				     ;; the instruction
				     #;(or (assq (byte-cell-adr dst) ;; TODO eliminating instructions does not work, too many are eliminated, it seems
					       file-reg-names)
					 ;; if the instruction affects the
					 ;; carry, it must be generated
					 (memq id carry-affecting-instrs)
					 ;; destination is used
					 (bitset-member?
					  (instr-live-after instr)
					  (byte-cell-id dst)))))
                            (or (not (byte-cell? src1))
                                (byte-cell-adr src1))
                            (or (not (byte-cell? src2))
                                (byte-cell-adr src2)))

                       (case id

                         ((move)
                          (if (byte-lit? src1)
                              (let ((n (byte-lit-val src1))
                                    (z (byte-cell-adr dst)))
                                (move-lit n z))
                              (let ((x (byte-cell-adr src1))
                                    (z (byte-cell-adr dst)))
                                (move-reg x z))))

                         ((add addc sub subb)
                          (if (byte-lit? src2)
                              (let ((n  (byte-lit-val src2))
                                    (z  (byte-cell-adr dst)))
				(if (byte-lit? src1)
				    (move-lit (byte-lit-val src1) z)
				    (move-reg (byte-cell-adr src1) z))
				(if (and (= n 0) ; nop
					 (or (eq? id 'add)
					     (eq? id 'sub)))
				    (set! ignore-carry-borrow? #t)
				    (begin
				      (case id
					((add)  (cond ((= n 1)    (incf z))
						      ;; ((= n #xff) (decf z)) ;; TODO set the carry
						      (else       (movlw n)
								  (addwf z))))
					((addc)
					 (movlw n)
					 (if ignore-carry-borrow?
					     (addwf  z)
					     (addwfc z)))
					((sub)  (cond ((= n 1)    (decf z))
						      ;; ((= n #xff) (incf z)) ;; TODO same
						      (else       (movlw n)
								  (subwf z))))
					((subb)
					 (movlw n)
					 (if ignore-carry-borrow?
					     (subwf  z)
					     (subwfb z))))
				      (set! ignore-carry-borrow? #f))))
                              (let ((x (or (and (byte-cell? src1) (byte-cell-adr src1)) 0)) ;; FOO this should not be needed (or correct), but without it, PICOBIT without bignums won't compile. it gives the right results for the vectors test, haven't checked the others.
                                    (y (byte-cell-adr src2))
                                    (z (byte-cell-adr dst)))
                                (cond ((and (not (= x y))
                                            (= y z)
                                            (memq id '(add addc)))
                                       ;; since this basically swaps the
                                       ;; arguments, it can't be used for
                                       ;; subtraction
                                       (move-reg x WREG))
                                      ((and (not (= x y))
                                            (= y z))
                                       ;; for subtraction, preserves argument
                                       ;; order
                                       (move-reg y WREG)
                                       ;; this NEEDS to be done with movff, or
                                       ;; else wreg will get clobbered and this
                                       ;; won't work
                                       (move-reg x z))
                                      (else ;; TODO check if it could be merged with the previous case
                                       (move-reg x z)
                                       (move-reg y WREG)))
                                (case id
                                  ((add)  (addwf z))
                                  ((addc) (if ignore-carry-borrow?
					      (addwf  z)
					      (addwfc z)))
                                  ((sub)  (subwf z))
                                  ((subb) (if ignore-carry-borrow?
					      (subwf  z)
					      (subwfb z)))
                                  (else   (error "...")))
				(set! ignore-carry-borrow? #f))))

                         ((mul) ; 8 by 8 multiplication
                          (if (byte-lit? src2)
                              ;; since multiplication is commutative, the
                              ;; arguments are set up so the second one will
                              ;; be a literal if the operator is applied on a
                              ;; literal and a variable
                              (let ((n (byte-lit-val src2)))
                                (if (byte-lit? src1)
                                    (movlw   (byte-lit-val src1))
                                    (move-reg (byte-cell-adr src1) WREG))
                                ;; literal multiplication
                                (mullw n))
                              (let ((x (byte-cell-adr src1))
                                    (y (byte-cell-adr src2)))
                                (move-reg x WREG)
                                (mulwf y))))

                         ((and ior xor)
                          (let* ((x  (if (byte-lit? src1)
					 (byte-lit-val src1)
					 (byte-cell-adr src1)))
				 (y  (if (byte-lit? src2)
					 (byte-lit-val src2)
					 (byte-cell-adr src2)))
				 (z  (byte-cell-adr dst))
				 (f  (case id
				       ((and) andwf)
				       ((ior) iorwf)
				       ((xor) xorwf)
				       (else (error "...")))))
			    (if (byte-lit? src2)
				(cond ((byte-lit? src1)
				       ;; low-level constant folding
				       (move-lit ((case id
						    ((and) bitwise-and)
						    ((ior) bitwise-ior)
						    ((xor) bitwise-xor))
						  x y)
						 z))
				      ((or (and (eq? id 'and) (= y #xff))
					   (and (eq? id 'ior) (= y #x00)))
				       ;; nop, just move the value
				       (move-reg x z))
				      ((and (eq? id 'and)
					    (= y #x00))
				       (clrf z))
				      ((and (eq? id 'ior) (= y #xff))
				       (setf z))
				      ;; use bit-set or bit-toggle
				      ((and (memq id '(ior xor))
					    ;; a single bit is set
					    (memq y '(#x01 #x02 #x04 #x08
						      #x10 #x20 #x40 #x80))
					    (eq? x z))
				       ((if (eq? id 'ior) bsf btg)
					z (inexact->exact
					   (/ (log y) (log 2)))))
				      ;; use bit-clear
				      ((and (eq? id 'and)
					    ;; a single bit is unset
					    (memq y '(#x7f #xbf #xdf #xef
						      #xf7 #xfb #xfd #xfe))
					    (eq? x z))
				       (bcf z (inexact->exact
					       (/ (log (- #xff y))
						  (log 2))))) ;; TODO since this requires x and z to be in the same place to be efficient, maybe coalesce theses cases in priority ? for now, this optimization does not save much
				      (else
				       (move-reg x z)
				       (movlw y)
				       (f z)))
				(begin (if (and (not (= x y)) (= y z))
					   (move-reg x WREG)
					   (begin
					     (move-reg x z)
					     (move-reg y WREG)))
				       (f z)))))

                         ((shl shr)
                          (let ((x (if (byte-lit? src1)
                                       (byte-lit-val src1)
                                       (byte-cell-adr src1)))
                                (z (byte-cell-adr dst)))
                            (cond ((byte-lit? src1) (move-lit x z))
                                  ((not (= x z))    (move-reg x z)))
                            (case id
                              ((shl) (rlcf z))
                              ((shr) (rrcf z)))))

                         ((set clear toggle)
                          ;; bit operations
                          (if (not (byte-lit? src2))
                              (error "bit offset must be a literal"))
                          (let ((x (byte-cell-adr src1))
                                (y (byte-lit-val src2)))
                            (case id
                              ((set)    (bsf x y))
                              ((clear)  (bcf x y))
                              ((toggle) (btg x y)))))

                         ((not)
                          (let ((z (byte-cell-adr dst)))
                            (if (byte-lit? src1)
                                (move-lit (byte-lit-val  src1) z)
                                (move-reg (byte-cell-adr src1) z))
                            (comf z)))

			 ((tblrd)
			  (if (byte-lit? src1)
			      (move-lit (byte-lit-val  src1) TBLPTRL)
			      (move-reg (byte-cell-adr src1) TBLPTRL))
			  (if (byte-lit? src2)
			      (move-lit (byte-lit-val  src2) TBLPTRH)
			      (move-reg (byte-cell-adr src2) TBLPTRH))
			  ;; TODO the 5 high bits are not used for now
			  (tblrd))

                         ((goto)
                          (if (null? (bb-succs bb))
                              (error "I think you might have given me an empty source file."))
                          (let* ((succs (bb-succs bb))
                                 (dest (car succs)))
                            (bra-or-goto (bb-label dest))
                            (add-todo dest)))
                         ((x==y x<y x>y)
                          (let* ((succs (bb-succs bb))
                                 (dest-true (car succs))
                                 (dest-false (cadr succs)))

                            (define (compare flip adr)
                              (case id
                                ((x<y) (if flip (cpfsgt adr) (cpfslt adr)))
                                ((x>y) (if flip (cpfslt adr) (cpfsgt adr)))
                                (else (cpfseq adr)))
                              (bra-or-goto (bb-label dest-false))
                              (bra-or-goto (bb-label dest-true))
                              (add-todo dest-false)
			      (add-todo dest-true))
			    
                            (cond ((byte-lit? src1)
                                   (let ((n (byte-lit-val src1))
                                         (y (byte-cell-adr src2)))
                                     (if #f #;(and (or (= n 0) (= n 1) (= n #xff))
                                         (eq? id 'x==y))
					 (special-compare-eq-lit n x)
					 (begin
					   (movlw n)
					   (compare #t y)))))
				  ((byte-lit? src2)
				   (let ((x (byte-cell-adr src1))
					 (n (byte-lit-val src2)))
				     (if #f #;(and (or (= n 0) (= n 1) (= n #xff))
					 (eq? id 'x==y))
					 (special-compare-eq-lit n x)
					 (begin
					   (movlw n)
					   (compare #f x)))))
				  (else
				   (let ((x (byte-cell-adr src1))
					 (y (byte-cell-adr src2)))
				     (move-reg y WREG)
				     (compare #f x))))))

			 ((branch-if-carry)
			  (let* ((succs      (bb-succs bb))
                                 (dest-true  (car succs))
                                 (dest-false (cadr succs))
				 ;; scratch is always a byte cell
				 (scratch    (byte-cell-adr src1)))
			    ;; note : bc is too short for some cases
			    ;; (bc (bb-label dest-true))
			    ;; (bra-or-goto (bb-label dest-false))
			    ;; instead, we use scratch to indirectly test the
			    ;; carry and use regular branches
			    (clrf scratch)
			    (clrf WREG)
			    (addwfc scratch)
			    (cpfsgt scratch)
			    (bra-or-goto (bb-label dest-false))
			    (bra-or-goto (bb-label dest-true))
			    (add-todo dest-false)
			    (add-todo dest-true)))

			 ((branch-table)
			  (let* ((off     (if (byte-lit? src1) ; branch no
					      (byte-lit-val  src1)
					      (byte-cell-adr src1)))
				 (scratch (byte-cell-adr src2)) ; working space
				 (succs   (bb-succs bb))
				 (n-succs (length succs)))


;; 			    ;; size of the branch table (without the
;; 			    ;; offset-calculating code), if it uses short jumps
;; 			    ;; that take 2 bytes per instruction
;; 			    (let ((size-using-bra  (* 2 n-succs))
;; 				  ;; size of the offset-calculating code, if we
;; 				  ;; use short jumps
;; 				  (bra-header-size ))
			      
;; 			      (asm-at-assembly
;; 			       ;; check if the targets are close enough to use
;; 			       ;; short jumps. all the targets must be close
;; 			       ;; enough, since all jumps must be of the same
;; 			       ;; size
;; 			       (lambda (self)
;; 				 (foldl
;; 				  (lambda (acc new)
;; 				    (and acc
;; 					 (let ((dist (- (label-pos (car new))
;; 							(+ self (cdr new)))))
;; 					   ;; close enough for short jumps
;; 					   (if (and (>= dist -2048)
;; 						    (<= dist 2047)
;; 						    (even? dist))
;; 					       2
;; 					       #f))))
;; 					#t
;; 					(map
;; 					 (lambda (l n)
;; 					   (cons l (+ self n bra-header-size)))
;; 					 succs (iota n-succs)))))) ;; FOO no time for this for the moment
			    
			    
			    ;; precalculate the low byte of the PC
			    ;; note: both branches (off is a literal or a
			    ;; register) are of the same length in terms of
			    ;; code, which is important
			    (if (byte-lit? src1)
				(movlw off)
				(movfw off))
			    ;; we add 4 times the offset, since gotos are 4
			    ;; bytes long
			    (if (byte-lit? src1)
				(begin (movlw off)
				       (movwf scratch))
				(movff off scratch))
			    (addwf scratch)
			    (addwf scratch)
			    (addwf scratch)
			    ;; to compensate for the PC advancing while we calculate
			    (movlw 10)
			    (addwf scratch)
			    (movfw PCL) ;; TODO at assembly, this can all be known statically
			    (addwf scratch)
			    (clrf WREG)
			    (addwfc PCLATH)
			    (movff scratch PCL)
			    
			    ;; create the jump table
			    (for-each (lambda (bb)
					(goto (bb-label bb))
					(add-todo bb))
				      succs)))
			 
			 (else
			  ;; ...
			  (emit (list id)))))))))

    (if bb
        (begin
          (vector-set! bbs-vector label-num #f)
          (label (bb-label bb))
          (for-each dump-instr (reverse (bb-rev-instrs bb))))))))

(let ((prog-label (asm-make-label 'PROG)))
  (rcall prog-label)
  (sleep)
  (label prog-label))

(add-todo (vector-ref bbs-vector 0))

(let loop ()
  (if (null? todo)
      (reverse rev-code)
      (let ((bb (car todo)))
        (set! todo (cdr todo))
        (bb-linearize bb)
        (loop)))))


(define (assembler-gen filename cfg)

  (define (gen instr)
    (define (gen-1-arg)
      ((eval (car instr)) (cadr instr)))
    (define (gen-2-args)
      ((eval (car instr)) (cadr instr) (caddr instr)))
    (define (gen-3-args)
      ((eval (car instr)) (cadr instr) (caddr instr) (cadddr instr)))

    (let ((id (car instr)))
      ;; count instructions by kind
      (table-set! concrete-instructions-counts id
		  (+ (table-ref concrete-instructions-counts id 0) 1))
      (case id
	((movlw mullw)
	 (gen-1-arg))
	((movff movwf clrf setf cpfseq cpfslt cpfsgt mulwf)
	 (gen-2-args))
	((incf decf addwf addwfc subwf subwfb andwf iorwf xorwf rlcf rrcf comf
	       bcf bsf btg movf)
	 (gen-3-args))
	((tblrd)
	 (tblrd*)) ;; TODO support the other modes
	((bc)
	 (bc (cadr instr)))
	((bra)
	 (bra (cadr instr)))
	((goto)
	 (goto (cadr instr)))
	((bra-or-goto)
	 (bra-or-goto (cadr instr)))
	((rcall)
	 (rcall-or-call (cadr instr)))
	((return)
	 (return))
	((label)
	 (asm-listing
	  (string-append (symbol->string (asm-label-id (cadr instr))) ":"))
	 (asm-label (cadr instr)))
	((sleep)
	 (sleep))
	(else
	 (error "unknown instruction" instr)))))

  (asm-begin! 0 #f)

  ;; (pretty-print cfg)
  
  (let ((code (linearize-and-cleanup cfg)))
    ;; (pretty-print code)
    ;; if we would need a second bank, load the address for the second bank in BSR
    (if bank-1-used?
	(begin (gen (list 'movlw 1))
	       (gen (list 'movwf BSR 'a))))
    (for-each gen code)))
