(in-package :lisp-on-lines)

;;;; * DESCRIPTIONS
;;;; A description is an object which is used 
;;;; to describe another object.


;;; #+HACK
;;; I'm having some 'issues' with 
;;; compiled code and my initialization.
;;; So this hack initializes the world.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *defined-descriptions* nil))

(define-layered-class description-access-class (standard-layer-class contextl::special-layered-access-class )
  ((defined-in-descriptions :initarg :in-description)
   (mixin-class-p :initarg :mixinp)))

(defmethod direct-slot-definition-class
           ((class description-access-class) &key &allow-other-keys)
  (find-class 'direct-attribute-definition-class))

(defmethod effective-slot-definition-class
           ((class description-access-class) &key &allow-other-keys)
  (find-class 'effective-attribute-definition-class))

(defmethod compute-effective-slot-definition
           ((class description-access-class) name direct-slot-definitions)
  (declare (ignore name))
  (let ((attribute (call-next-method)))
    (setf (attribute-direct-attributes attribute) direct-slot-definitions)
    (setf (attribute-object-initargs attribute)  
	  ;; This plist will be used to init the attribute object
          ;; Once the description itself is properly initiated.
	  (list :name name 
		'effective-attribute attribute))
    attribute))

(defmethod slot-value-using-class ((class description-access-class) object slotd)
        (call-next-method)
#+nil  (if (or 
       (eq (slot-definition-name slotd) 'described-object)
       (not (slot-boundp slotd 'attribute-object)))
      (call-next-method)
      (slot-definition-attribute-object slotd)))
    

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *description-attributes* (make-hash-table)))



(defclass standard-description-class (description-access-class layered-class)
  ((attributes :accessor description-class-attributes :initform (list)))
  (:default-initargs :defining-metaclass 'description-access-class))



(defmethod validate-superclass
           ((class standard-description-class)
            (superclass standard-class))
  t)

(define-layered-class standard-description-object (standard-layer-object) 
  ((described-object :accessor described-object 
		     :special t)))

(defun description-class-name  (description-class)
    (read-from-string (symbol-name (class-name description-class))))

(defgeneric standard-description-p (description-candidate)
  (:method (not-description)
    NIL)
  (:method ((description standard-description-object))
    T))
  
(defun initialize-description-class (class)

;;; HACK: initialization does not happ   en properly 
;;; when compiling and loading or something like that.
;;; Obviously i'm not sure why.
;;; So we're going to explicitly initialize things.
;;; For now. --drewc

  (pushnew class *defined-descriptions*)

;;; ENDHACK.
  
  (let* ((description (find-layer class)) 
	 (attribute-objects 
	  (setf (description-class-attributes (class-of description))
		(mapcar 
		 (lambda (slot)
		   (or (find-attribute description 
				       (slot-definition-name slot))
		       (let* ((*init-time-description* description)
			      (attribute-class (or 
						(ignore-errors 
						  (slot-value-using-class 
						   (class-of description) description slot))
						'standard-attribute))
			      (attribute 		     
			       (apply #'make-instance 
				      attribute-class
				      :description description
				      :attribute-class attribute-class
				      (attribute-object-initargs slot))))
			 (setf (slot-definition-attribute-object slot) attribute))))
		 (remove 'described-object (class-slots (class-of description))
			 :key #'slot-definition-name))))
	 (defining-classes 
	  (partial-class-defining-classes class)))

    (loop 
       :for (layer class) 
       :on  defining-classes :by #'cddr 
       :do (funcall-with-layer-context 
	    (adjoin-layer (find-layer layer) (current-layer-context))
	    (lambda ()
	      (loop :for direct-slot :in (class-direct-slots class) 
		 :do (let ((attribute 
			    (find (slot-definition-name direct-slot) 
				  attribute-objects 
				  :key #'attribute-name)))
		       (let ((initargs 
			      (prepare-initargs attribute (direct-attribute-properties direct-slot))))
			 
			 (apply #'reinitialize-instance attribute 
				initargs )
			 (setf (slot-value description (attribute-name attribute)) 
			       (attribute-class attribute))
			 (apply #'change-class attribute  (attribute-class attribute)
				initargs)))))))))


#+old(defun initialize-description-class (class)

;;; HACK: initialization does not happ   en properly 
;;; when compiling and loading or something like that.
;;; Obviously i'm not sure why.
;;; So we're going to explicitly initialize things.
;;; For now. --drewc

  (pushnew class *defined-descriptions*)

;;; ENDHACK.

  (let* ((description (find-layer class)) 
	 (attribute-objects 
	  (mapcar 
	   (lambda (slot)
	     (let* ((*init-time-description* description)
			  (attribute 		     
			   (apply #'make-instance 
			    'standard-attribute
			    :description description
			    (attribute-object-initargs slot))))
	       
		     
	       (setf (slot-definition-attribute-object slot) attribute)))
	   (remove 'described-object (class-slots (class-of description))
		   :key #'slot-definition-name)))
	 (defining-classes (partial-class-defining-classes (class-of description))))

    (loop 
       :for (layer class) 
       :on  defining-classes :by #'cddr 
       :do (funcall-with-layer-context 
	    (adjoin-layer (find-layer layer) (current-layer-context))
	    (lambda ()
	      (loop :for direct-slot :in (class-direct-slots class) 
		 :do (let ((attribute 
			    (find (slot-definition-name direct-slot) 
				  attribute-objects 
				  :key #'attribute-name)))
		       (let ((initargs 
			      (prepare-initargs attribute (direct-attribute-properties direct-slot))))
			 
			 (apply #'reinitialize-instance attribute 
				initargs )
			 (warn "Attribute class for ~A is ~A" attribute (attribute-class attribute))
			 (when (not (eq (find-class (attribute-class attribute))
					(class-of attribute)))
			   (warn "~%CHANGING CLASS~%")
			   
			   (apply #'change-class attribute  (attribute-class attribute) 
				  initargs))))))))))

;;;; HACK: run this at startup till we figure things out.
(defun initialize-descriptions () 
  (map nil #'initialize-description-class 
       (setf *defined-descriptions* 
	     (remove-duplicates *defined-descriptions*))))

(defmethod initialize-instance :around ((class standard-description-class) &rest initargs &key (direct-superclasses '()))
  (declare (dynamic-extent initargs))
  (prog1
      (if (loop for direct-superclass in direct-superclasses
		thereis (ignore-errors (subtypep direct-superclass 'standard-description-object)))
	(call-next-method)
	(apply #'call-next-method
	       class
	       :direct-superclasses
	       (append direct-superclasses
		       (list (find-class 'standard-description-object)))
	       initargs))
    (initialize-description-class class)))


(defmethod reinitialize-instance :around ((class standard-description-class) &rest initargs &key (direct-superclasses '() direct-superclasses-p))
  (declare (dynamic-extent initargs))
;  (warn "CLASS ~A ARGS ~A:" class initargs)
  (prog1
      (if (or (not direct-superclasses-p)
		(loop for direct-superclass in direct-superclasses
		      thereis (ignore-errors (subtypep direct-superclass 'standard-description-object))))
	  (call-next-method)
	  (apply #'call-next-method
		 class
		 :direct-superclasses
		 (append direct-superclasses
			 (list (find-class 'standard-description-object)))
		 initargs))
    (initialize-description-class class)))
		      
		      
(defmethod print-object ((object standard-description-object) stream)
  (print-unreadable-object (object stream :type nil :identity t)
    (format stream "DESCRIPTION ~A" (ignore-errors (description-print-name object)))))

(defmethod print-object ((object standard-description-class) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (princ  (ignore-errors (description-print-name (find-layer object))) stream)))

(defun find-description (name)
  (find-layer (find-class (defining-description name))))






