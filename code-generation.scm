;; address after which memory is allocated by the user, therefore not used for
;; register allocation
;; in programs, located in the SIXPIC_MEMORY_DIVIDE variable
(define memory-divide #f)

(define (interference-graph cfg)

  (define all-live '())

  (define (interfere x y)
    (if (not (memq x (byte-cell-interferes-with y)))
        (begin
          (byte-cell-interferes-with-set!
           x
           (cons y (byte-cell-interferes-with x)))
          (byte-cell-interferes-with-set!
           y
           (cons x (byte-cell-interferes-with y))))))

  (define (interfere-pairwise live)
    (set! all-live (union all-live live))
    (for-each (lambda (x)
                (for-each (lambda (y)
                            (if (not (eq? x y))
                                (interfere x y)))
                          live))
              live))

  (define (instr-interference-graph instr)
    (let ((dst (instr-dst instr)))
      (if (byte-cell? dst)
          (let ((src1 (instr-src1 instr))
                (src2 (instr-src2 instr)))
            (if (byte-cell? src1)
                (begin
                  (byte-cell-coalesceable-with-set!
                   dst
                   (union (byte-cell-coalesceable-with dst)
                          (list src1)))
                  (byte-cell-coalesceable-with-set!
                   src1
                   (union (byte-cell-coalesceable-with src1)
                          (list dst)))))
            (if (byte-cell? src2)
                (begin
                  (byte-cell-coalesceable-with-set!
                   dst
                   (union (byte-cell-coalesceable-with dst)
                          (list src2)))
                  (byte-cell-coalesceable-with-set!
                   src2
                   (union (byte-cell-coalesceable-with src2)
                          (list dst))))))))
    (let ((live-before (instr-live-before instr)))
      (interfere-pairwise live-before)))

  (define (bb-interference-graph bb)
    (for-each instr-interference-graph (bb-rev-instrs bb)))

  (analyze-liveness cfg)

  (for-each bb-interference-graph (cfg-bbs cfg))

  all-live)

(define (allocate-registers cfg)
  (let ((all-live (interference-graph cfg)))

    (define (color byte-cell)
      (let ((coalesce-candidates ; TODO right now, no coalescing is done
             (keep byte-cell-adr
                   (diff (byte-cell-coalesceable-with byte-cell)
                         (byte-cell-interferes-with byte-cell)))))
        '
        (pp (list byte-cell: byte-cell;;;;;;;;;;;;;;;
                  coalesce-candidates
;                  interferes-with: (byte-cell-interferes-with byte-cell)
;                  coalesceable-with: (byte-cell-coalesceable-with byte-cell)
		  ))

        (if #f #;(not (null? coalesce-candidates))
            (let ((adr (byte-cell-adr (car coalesce-candidates))))
              (byte-cell-adr-set! byte-cell adr))
            (let ((neighbours (byte-cell-interferes-with byte-cell)))
              (let loop1 ((adr 0))
		(if (and memory-divide ; the user wants his own zone
			 (>= adr memory-divide)) ; and we'd use it
		    (error "register allocation would cross the memory divide") ;; TODO fallback ?
		    (let loop2 ((lst neighbours))
		      (if (null? lst)
			  (byte-cell-adr-set! byte-cell adr)
			  (let ((x (car lst)))
			    (if (= adr (byte-cell-adr x))
				(loop1 (+ adr 1))
				(loop2 (cdr lst))))))))))))

    (define (delete byte-cell1 neighbours)
      (for-each (lambda (byte-cell2)
                  (let ((lst (byte-cell-interferes-with byte-cell2)))
                    (byte-cell-interferes-with-set!
                     byte-cell2
                     (remove byte-cell1 lst))))
                neighbours))

    (define (undelete byte-cell1 neighbours)
      (for-each (lambda (byte-cell2)
                  (let ((lst (byte-cell-interferes-with byte-cell2)))
                    (byte-cell-interferes-with-set!
                     byte-cell2
                     (cons byte-cell1 lst))))
                neighbours))

    (define (find-min-neighbours graph)
      (let loop ((lst graph) (m #f) (byte-cell #f))
        (if (null? lst)
            byte-cell
            (let* ((x (car lst))
                   (n (length (byte-cell-interferes-with x))))
              (if (or (not m) (< n m))
                  (loop (cdr lst) n x)
                  (loop (cdr lst) m byte-cell))))))

    (define (alloc-reg graph)
      (if (not (null? graph))
          (let* ((byte-cell (find-min-neighbours graph))
                 (neighbours (byte-cell-interferes-with byte-cell)))
            (let ((new-graph (remove byte-cell graph)))
              (delete byte-cell neighbours)
              (alloc-reg new-graph)
              (undelete byte-cell neighbours))
            (if (not (byte-cell-adr byte-cell))
                (color byte-cell)))))

    (alloc-reg all-live)))


(define (linearize-and-cleanup cfg)

  (define bbs-vector (cfg->vector cfg))

  (define todo '())

  (define (add-todo bb)
    (set! todo (cons bb todo)))

  (define rev-code '())

  (define (emit instr)
    (set! rev-code (cons instr rev-code)))

  (define (movlw val)
    (emit (list 'movlw val)))
  (define (movwf adr)
    (emit (list 'movwf adr)))
  (define (movfw adr)
    (emit (list 'movfw adr)))
  (define (movff src dst)
    (emit (list 'movff src dst)))

  (define (clrf adr)
    (emit (list 'clrf adr)))
  (define (setf adr)
    (emit (list 'setf adr)))

  (define (incf adr)
    (emit (list 'incf adr)))
  (define (decf adr)
    (emit (list 'decf adr)))

  (define (addwf adr)
    (emit (list 'addwf adr)))
  (define (addwfc adr)
    (emit (list 'addwfc adr)))

  (define (subwf adr)
    (emit (list 'subwf adr)))
  (define (subwfb adr)
    (emit (list 'subwfb adr)))

  (define (mullw adr)
    (emit (list 'mullw adr)))
  (define (mulwf adr)
    (emit (list 'mulwf adr)))

  (define (andwf adr)
    (emit (list 'andwf adr)))
  (define (iorwf adr)
    (emit (list 'iorwf adr)))
  (define (xorwf adr)
    (emit (list 'xorwf adr)))
  
  (define (cpfseq adr)
    (emit (list 'cpfseq adr)))
  (define (cpfslt adr)
    (emit (list 'cpfslt adr)))
  (define (cpfsgt adr)
    (emit (list 'cpfsgt adr)))

  (define (bra label)
    (emit (list 'bra label)))

  (define (rcall label)
    (emit (list 'rcall label)))

  (define (return)
    (if (and #f (and (not (null? rev-code)) ; TODO probably here for eventual inlining
		     (eq? (caar rev-code) 'rcall)))
        (let ((label (cadar rev-code)))
          (set! rev-code (cdr rev-code))
          (bra label))
        (emit (list 'return))))

  (define (label lab)
    (if (and #f (and (not (null? rev-code)) ; TODO would probably be useful to eliminate things like : bra $2, $2: 
             (eq? (caar rev-code) 'bra)
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
           (movfw src)
	   (movwf dst)
	   ;(movff src dst) ; takes 2 cycles (as much as movfw src ; movwf dst), but takes only 1 instruction TODO not implemented in the simulator
	   )))

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
                       (dst (instr-dst instr)))
                   (if (and (or (not (byte-cell? dst))
                                (byte-cell-adr dst))
                            (or (not (byte-cell? src1))
                                (byte-cell-adr src1))
                            (or (not (byte-cell? src2))
                                (byte-cell-adr src2)))

                       (case (instr-id instr)
			 
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
                              (let ((n (byte-lit-val src2))
                                    (z (byte-cell-adr dst)))
                                (if (byte-lit? src1)
                                    (move-lit (byte-lit-val src1) z)
                                    (move-reg (byte-cell-adr src1) z))
                                (case (instr-id instr)
                                  ((add)  (cond ((= n 1)    (incf z))
						((= n #xff) (decf z))
						(else       (movlw n)
							    (addwf z))))
                                  ((addc) (movlw n) (addwfc z))
                                  ((sub)  (cond ((= n 1)    (decf z))
						((= n #xff) (incf z))
						(else       (movlw n)
							    (subwf z))))
                                  ((subb) (movlw n) (subwfb z))))
                              (let ((x (byte-cell-adr src1))
                                    (y (byte-cell-adr src2))
                                    (z (byte-cell-adr dst)))
                                (cond ((and (not (= x y)) (= y z))
                                       (move-reg x WREG))
                                      (else
                                       (move-reg x z)
                                       (move-reg y WREG)))
				(case (instr-id instr) ;; TODO used to be in each branch of the cond, now is abstracted test to see if it still works
				  ((add)  (addwf z))
				  ((addc) (addwfc z))
				  ((sub)  (subwf z))
				  ((subb) (subwfb z))
				  (else   (error "..."))))))
			 
			 ((mul) ; 8 by 8 multiplication
			  (if (byte-lit? src2)
                              (let ((n (byte-lit-val src2)))
                                (if (byte-lit? src1) ;; TODO will probably never be called with literals, since it's always inside a function
				    (movlw   (byte-lit-val src1))
                                    (movereg (byte-cell-adr src1) WREG))
				;; literal multiplication
				(mullw n))
                              (let ((x (byte-cell-adr src1)) ;; TODO how to be sure that we can't get the case of the 1st arg being a literal, but not the 2nd ?
                                    (y (byte-cell-adr src2)))
				(move-reg x WREG)
				(mulwf y)))) ;; TODO seems to take the same argument twice, see test32
			 
			 ((and ior xor) ;; TODO similar to add sub and co, except that I removed the literal part
			  (let ((x (if (byte-lit? src1)
				       (byte-lit-val src1)
				       (byte-cell-adr src1)))
				(y (if (byte-lit? src2)
				       (byte-lit-val src2)
				       (byte-cell-adr src2)))
				(z (byte-cell-adr dst)))
			    (cond ((byte-lit? src1)
				   (if (byte-lit? src2)
				       (move-lit y z)
				       (move-reg y z))
				   (movlw x)) ;; TODO not sure it will work
				  ((and (not (= x y)) (= y z))
				   (move-reg x WREG))
				  (else
				   (move-reg x z)
				   (move-reg y WREG)))
			    (case (instr-id instr)
			      ((and) (andwf z))
			      ((ior) (iorwf z))
			      ((xor) (xorwf z))
			      (else (error "...")))))
			 
                         ((goto)
                          (let* ((succs (bb-succs bb))
                                 (dest (car succs)))
                            (bra (bb-label dest))
                            (add-todo dest)))
                         ((x==y x<y x>y)
                          (let* ((succs (bb-succs bb))
                                 (dest-true (car succs))
                                 (dest-false (cadr succs)))

                            (define (compare flip adr)
                              (case (instr-id instr)
                                ((x<y) (if flip (cpfsgt adr) (cpfslt adr)))
                                ((x>y) (if flip (cpfslt adr) (cpfsgt adr)))
                                (else (cpfseq adr)))
                              (bra (bb-label dest-false))
                              (bra (bb-label dest-true))
                              (add-todo dest-false)
                              (add-todo dest-true))

                            (cond ((byte-lit? src1)
                                   (let ((n (byte-lit-val src1))
                                         (y (byte-cell-adr src2)))
                                     (if #f #;(and (or (= n 0) (= n 1) (= n #xff))
                                              (eq? (instr-id instr) 'x==y))
                                         (special-compare-eq-lit n x)
                                         (begin
                                           (movlw n)
                                           (compare #t y)))))
                                  ((byte-lit? src2)
                                   (let ((x (byte-cell-adr src1))
                                         (n (byte-lit-val src2)))
                                     (if #f #;(and (or (= n 0) (= n 1) (= n #xff))
                                              (eq? (instr-id instr) 'x==y))
                                         (special-compare-eq-lit n x) ;; TODO does not exist. the only way apart from cpfseq I see would be to load w, do a subtraction, then conditional branch, but would be larger and would take 1-2 cycles more
                                         (begin
                                           (movlw n)
                                           (compare #f x)))))
                                  (else
                                   (let ((x (byte-cell-adr src1))
                                         (y (byte-cell-adr src2)))
                                     (move-reg y WREG)
                                     (compare #f x))))))
                         (else
                          ;...
                          (emit (list (instr-id instr))))))))))

        (if bb
            (begin
              (vector-set! bbs-vector label-num #f)
              (label (bb-label bb))
              (for-each dump-instr (reverse (bb-rev-instrs bb)))
              (for-each add-todo (bb-succs bb)))))))
  
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
    (case (car instr)
      ((movlw)
       (movlw (cadr instr)))
      ((movwf)
       (movwf (cadr instr)))
      ((movfw)
       (movf (cadr instr) 'w))
      ((movff)
       (movff (cadr instr) (caddr instr)))
      ((clrf)
       (clrf (cadr instr)))
      ((setf)
       (setf (cadr instr)))
      ((incf)
       (incf (cadr instr)))
      ((decf)
       (decf (cadr instr)))
      ((addwf)
       (addwf (cadr instr)))
      ((addwfc)
       (addwfc (cadr instr)))
      ((subwf)
       (subwf (cadr instr)))
      ((subwfb)
       (subwfb (cadr instr)))
      ((mullw)
       (mullw (cadr instr)))
      ((mulwf)
       (mulwf (cadr instr)))
      ((andwf)
       (andwf (cadr instr)))
      ((iorwf)
       (iorwf (cadr instr)))
      ((xorwf)
       (xorwf (cadr instr)))
      ((cpfseq)
       (cpfseq (cadr instr)))
      ((cpfslt)
       (cpfslt (cadr instr)))
      ((cpfsgt)
       (cpfsgt (cadr instr)))
      ((bra)
       (bra (cadr instr)))
      ((rcall)
       (rcall (cadr instr)))
      ((return)
       (return))
      ((label)
       (asm-listing
        (string-append (symbol->string (asm-label-id (cadr instr))) ":"))
       (asm-label (cadr instr)))
      ((sleep)
       (sleep))
      (else
       (error "unknown instruction" instr))))

  (asm-begin! 0 #f)

;  (pretty-print cfg)

  (let ((code (linearize-and-cleanup cfg)))
;    (pretty-print code)
    (for-each gen code)))

(define (code-gen filename cfg)
  (allocate-registers cfg)
  (assembler-gen filename cfg)
;  (pretty-print cfg)
;  (pretty-print (reverse (bb-rev-instrs bb))) ;; TODO what ? there are no bbs here...
  )
