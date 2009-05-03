#!/usr/bin/env gsi

(include "pic18-sim.scm")
(include "utilities.scm")
(include "ast.scm")
(include "operators.scm")
(include "cte.scm")
(include "parser.scm")
(include "cfg.scm")
(include "optimizations.scm")
(include "code-generation.scm")


;------------------------------------------------------------------------------

;; temporary solution, to support more than int
(set! ##six-types ;; TODO unsigned types ?
  '((int    . #f)
    (byte   . #f)
    (int8   . #f)
    (int16  . #f)
    (int24  . #f) ;; TODO useful ? is currently used for 8x16 multiplications
    (int32  . #f)
    (char   . #f)
    (bool   . #f)
    (void   . #f)
    (float  . #f)
    (double . #f)
    (obj    . #f)))
;; TODO typedef should add to this list

(define (read-source filename)
  (shell-command (string-append "cpp -P " filename " > " filename ".tmp"))
;;   (##read-all-as-a-begin-expr-from-path ;; TODO use vectorized notation to have info on errors (where in the source)
;;    (string-append filename ".tmp")
;;    (readtable-start-syntax-set (current-readtable) 'six)
;;    ##wrap-datum
;;    ##unwrap-datum)
  (with-input-from-file
      (string-append filename ".tmp")
    (lambda ()
      (input-port-readtable-set!
       (current-input-port)
       (readtable-start-syntax-set
        (input-port-readtable (current-input-port))
        'six))
      (read-all)))
  )

(define (main filename)

  (output-port-readtable-set!
   (current-output-port)
   (readtable-sharing-allowed?-set
    (output-port-readtable (current-output-port))
    #t))

  (let ((source (read-source filename)))
    '(pretty-print source)
    (let* ((ast (parse source)))
      '(pretty-print ast)
      (let ((cfg (generate-cfg ast)))
	'(print-cfg-bbs cfg)
	'(pretty-print cfg)
        (remove-branch-cascades-and-dead-code cfg)
	(remove-converging-branches cfg)
	(remove-dead-instructions cfg)
	'(pp "AFTER")
	'(print-cfg-bbs cfg)
        '(pretty-print cfg)
        (let ((code (code-gen filename cfg)))
	  (asm-assemble)
	  '(display "------------------ GENERATED CODE\n")
	  (asm-display-listing (current-output-port))
	  (asm-write-hex-file (string-append filename ".hex"))
	  (asm-end!)
	  '(display "------------------ EXECUTION USING SIMULATOR\n")
	  (execute-hex-file (string-append filename ".hex"))
	  #t)))))
