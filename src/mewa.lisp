(declaim (optimize (speed 2) (space 3) (safety 0)))

(in-package :lisp-on-lines)

(defparameter *default-type* :ucw)

(define-layered-class description ()
  ((description-type
    :initarg :type
    :accessor description.type
    :initform 'viewer
    :special t)
   (description-layers
    :initarg :layers
    :accessor description.layers
    :initform nil
    :special t)
   (description-properties
    :accessor description.properties
    :initform nil
    :special t)
   (description-attributes
    :accessor attributes
    :initarg :attributes
    :initform nil
    :special t)))

(defmethod print-object ((self description) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (description-type) self
      (format t "~A" description-type))))

;;;; * Occurences

(defvar *occurence-map* (make-hash-table)
  "a display is generated by associating an 'occurence' 
with an instance of a class. This is usually keyed off class-name,
although an arbitrary occurence can be used with an arbitrary class.")

(define-layered-class
    standard-occurence (description)
    ((attribute-map :accessor attribute-map :initform (make-hash-table)))
    (:documentation
     "an occurence holds the attributes like a class holds slot-definitions.
Attributes are the metadata used to display, validate, and otherwise manipulate actual values stored in lisp objects."))

(defun find-or-create-occurence (name)
  "Returns the occurence associated with this name."
  (let ((occurence (gethash name *occurence-map*)))
    (if occurence
	occurence
	(let ((new-occurence (make-instance 'standard-occurence)))
	  (setf (gethash name *occurence-map*) new-occurence)
	  new-occurence))))

(defun clear-occurence (occurence)
  "removes all attributes from the occurence"
  (setf (attribute-map occurence) (make-hash-table)))

(defgeneric find-occurence (name)
  (:method (thing)
    nil)
  (:method ((name symbol))
    (find-or-create-occurence name))
  (:method ((instance standard-object))
    (find-or-create-occurence (class-name (class-of instance)))))


(define-layered-class
    attribute (description)
    ((name :layered-accessor attribute.name
	   :initarg :name
	   :initform (gensym "ATTRIBUTE-")
	   :special t)
     (occurence :accessor occurence :initarg :occurence :initform nil)
     (label :initarg :label :accessor label :initform nil :special t)))

;;;; * Attributes
(defmethod print-object ((self attribute) stream)
  (print-unreadable-object (self stream :type t)
    (with-slots (name description-type) self
      (format stream "~A ~A" description-type name))))

(define-layered-class
    standard-attribute (attribute)
    ((setter :accessor setter :initarg :setter :special t :initform nil)
     (getter :accessor getter :initarg :getter :special t :initform nil)
     (slot-name :accessor slot-name :initarg :slot-name :special t)
     (id :accessor id :initarg :id :special t :initform (random-string)))
    (:documentation "Attributes are used to display a part of a thing, such as a slot of an object, a text label, the car of a list, etc."))

(defmacro defattribute (name supers slots &rest args)
  (let ((type (or (second (assoc :type-name args)) name))
	(layer (or (second (assoc :in-layer args)) nil))
	(properties (cdr (assoc :default-properties args)))
	(cargs  (remove-if #'(lambda (key)
		   (or (eql key :type-name)
		       (eql key :default-properties)
		       (eql key :default-initargs)
		       (eql key :in-layer)))
			 args
	       :key #'car)))
    
    `(progn
      (define-layered-class
	  ;;;; TODO: fix the naive way of making sure s-a is a superclass
	  ;;;; Need some MOPey goodness.
	  ,name ,@ (when layer `(:in-layer ,layer)),(or supers '(standard-attribute))
	  ,(append slots (properties-as-slots properties)) 
	  #+ (or) ,@ (cdr cargs)
	  ,@cargs
	  (:default-initargs :properties (list ,@properties)
	    ,@ (cdr (assoc :default-initargs args))))

      (defmethod find-attribute-class-for-type ((type (eql ',type)))
	',name))))



(define-layered-class
    display-attribute (attribute)
    ()
    (:documentation "Presentation Attributes are used to display objects 
using the attributes defined in an occurence. Presentation Attributes are always named using keywords."))

(defun clear-attributes (name)
  "removes all attributes from an occurance"
  (clear-occurence (find-occurence name)))

(defmethod find-attribute-class-for-type (type)
  nil)

(defmethod find-attribute-class-for-name (name)
  "presentation attributes are named using keywords"
  (if (keywordp name)
      'display-attribute
      'standard-attribute))

(defun make-attribute (&rest args &key name type &allow-other-keys)
  (apply #'make-instance
	 (or (find-attribute-class-for-type type)
	     (find-attribute-class-for-name name))
	 args)) 

(defmethod ensure-attribute ((occurence standard-occurence) &rest args &key name &allow-other-keys)
  "Creates an attribute in the given occurence"
  (let ((attribute (apply #'make-attribute :occurence occurence args)))
    (setf (description.properties attribute) args)
    (setf (gethash name (attribute-map occurence))
	  attribute)))

(defmethod find-attribute ((occurence standard-occurence) name)
  (gethash name (attribute-map occurence)))

(defmethod find-all-attributes ((occurence standard-occurence))
  (loop for att being the hash-values of (attribute-map occurence)
	collect att))

(defmethod ensure-attribute (occurence-name &rest args &key name type &allow-other-keys)
  (declare (ignore name type))
  (apply #'ensure-attribute
   (find-occurence occurence-name)
   args)) 

;;;; The following functions make up the public interface to the
;;;; MEWA Attribute Occurence system.

(defmethod find-all-attributes (occurence-name)
  (find-all-attributes (find-occurence occurence-name)))

(defmethod find-attribute (occurence-name attribute-name)
  "Return the ATTRIBUTE named by ATTRIBUTE-NAME in OCCURANCE-name"
  (find-attribute (find-occurence occurence-name) attribute-name))

(defmethod (setf find-attribute) ((attribute-spec list) occurence-name attribute-name)
  "Create a new attribute in the occurence.
ATTRIBUTE-SPEC: a list of (type name &rest initargs)"
  (apply #'ensure-attribute occurence-name :name attribute-name :type (first attribute-spec) (rest attribute-spec)))


(defmethod find-attribute ((attribute-with-occurence attribute) attribute-name)
  (find-attribute (occurence attribute-with-occurence) attribute-name))

(defmethod set-attribute-properties ((occurence-name t) attribute properties)
  (setf (description.properties attribute) (plist-nunion
					    properties
					    (description.properties attribute)))
  (loop for (initarg value) on (description.properties attribute) 
	      by #'cddr
	      with map = (initargs.slot-names attribute)
	      do (let ((s-n (assoc-if #'(lambda (x) (member initarg x)) map)))
		   
		   (if s-n
		       (progn
			 (setf (slot-value attribute
					   (cdr s-n))
			       value))
		       (warn "Cannot find initarg ~A in attribute ~S" initarg attribute)))
	      finally (return attribute)))

(defmethod set-attribute (occurence-name attribute-name attribute-spec &key (inherit t))
  "If inherit is T, sets the properties of the attribute only, unless the type has changed.
otherwise, (setf find-attribute)"
  (let ((att (find-attribute occurence-name attribute-name)))
    (if (and att inherit (or (eql (car attribute-spec)
			      (description.type att))
			     (eq (car attribute-spec) t)))
	(set-attribute-properties occurence-name att (cdr attribute-spec))
	(setf (find-attribute occurence-name attribute-name)
	      (cons  (car attribute-spec)
		     (plist-nunion
		      (cdr attribute-spec) 
		      (when att (description.properties att))))))))

(defmethod perform-define-attributes ((occurence-name t) attributes)
  (loop for attribute in attributes
	do (destructuring-bind (name type &rest args)
		  attribute
	     (cond ((not (null type))
		    ;;set the type as well
		    (set-attribute occurence-name name (cons type args)))))))
		       
(defmacro define-attributes (occurence-names &body attribute-definitions)
  `(progn
    ,@(loop for occurence-name in occurence-names
	    collect `(perform-define-attributes (quote ,occurence-name) (quote ,attribute-definitions)))))

(defmethod find-display-attribute (occurence name)
  (find-attribute occurence (intern (symbol-name name) "KEYWORD")))

(defmethod find-description (object type)
  (let ((occurence (find-occurence object)))
    (or (find-display-attribute
	 occurence
	 type)
	occurence)))

(defmethod setter (attribute)
  (warn "Setting ~A in ~A" attribute *context*)
  (let ((setter (getf (description.properties attribute) :setter))
	(slot-name (getf (description.properties attribute) :slot-name)))
    (cond (setter
	   setter)
	  (slot-name
	   #'(lambda (value object)
	       (setf (slot-value object slot-name) value)))
	  (t
	   #'(lambda (value object)
	       (warn "Can't find anywere to set ~A in ~A using ~A" value object attribute))))))
    

(define-layered-function attribute-value (instance attribute)
  (:documentation " Like SLOT-VALUE for instances, the base method calls GETTER."))

(define-layered-method attribute-value (instance (attribute standard-attribute))
    (with-slots (getter slot-name) attribute 
      (cond ((and (slot-boundp attribute 'getter) getter) 
	     (funcall getter instance))
	    ((and (slot-boundp attribute 'slot-name) slot-name)
	     (when (slot-boundp instance slot-name)
		 (slot-value instance slot-name)))
	    ((and (slot-exists-p instance (attribute.name attribute)) )
	       (when (slot-boundp instance (attribute.name attribute))
		 (slot-value instance (attribute.name attribute)))))))

(define-layered-function (setf attribute-value)  (value instance attribute))

(define-layered-method
    (setf attribute-value) (value instance (attribute standard-attribute))
	       
  (with-slots (setter slot-name) attribute 
    (cond ((and (slot-boundp attribute 'setter) setter)

	   (funcall setter value instance))
	  ((and (slot-boundp attribute 'slot-name) slot-name)
	   (setf (slot-value instance slot-name) value))
	  ((and (slot-exists-p instance (attribute.name attribute)) slot-name)
	   (setf (slot-value instance (attribute.name attribute)) value))
	  (t
	   (error "Cannot set ~A in ~A" attribute instance)))))


;;;; ** Default Attributes


;;;; The default mewa class contains the types use as defaults.
;;;; maps meta-model slot-types to slot-presentation

(defvar *default-attributes-class-name* 'default)

(defmacro with-default-attributes ((occurence-name) &body body)
  `(let ((*default-attributes-class-name* ',occurence-name))
    ,@body))

(define-attributes (default)
  (boolean mewa-boolean)
  (string mewa-string)
  (number mewa-currency)
  (integer   mewa-integer)
  (currency  mewa-currency)
  (clsql:generalized-boolean mewa-boolean)
  (foreign-key foreign-key)
  (:viewer mewa-viewer)
  (:editor mewa-editor)
  (:creator mewa-creator)
  (:as-string mewa-one-line-presentation)
  (:one-line mewa-one-line-presentation)
  (:listing mewa-list-presentation :global-properties (:editablep nil) :editablep t)
  (:search-model mewa-object-presentation))

(defun find-presentation-attributes (occurence-name)
  (loop for att in (find-all-attributes occurence-name)
	when (typep att 'display-attribute)
	 collect att))

(defun attribute-to-definition (attribute)
  (nconc (list (attribute.name attribute)
	       (description.type attribute))
	 (description.properties attribute)))

(defun find-default-presentation-attribute-definitions ()
  (if (eql *default-attributes-class-name* 'default)
      (mapcar #'attribute-to-definition (find-presentation-attributes 'default)) 
      (remove-duplicates (mapcar #'attribute-to-definition
				 (append
				  (find-presentation-attributes 'default)
				  (find-presentation-attributes
				   *default-attributes-class-name*))))))
(defun gen-ptype (type)
  (let* ((type (if (consp type) (car type) type))
	 (possible-default (find-attribute *default-attributes-class-name* type))
	 (real-default (find-attribute 'default type)))
    (cond
      (possible-default
	(description.type possible-default))
       (real-default
	(description.type real-default))
       (t type))))

(defun gen-presentation-slots (instance)
  (mapcar #'(lambda (x) (gen-pslot (cadr x) 
				   (string (car x)) 
				   (car x))) 
	  (meta-model:list-slot-types instance)))


(defun gen-pslot (type label slot-name)
  (copy-list `(,(gen-ptype type) 
	       :label ,label
	       :slot-name ,slot-name))) 


	  
;;;; DEPRECIATED: Mewa presentations
;;;; this is legacy cruft. 


(defcomponent mewa ()
  ((instance :accessor instance :initarg :instance) 
   (attributes
    :initarg :attributes
    :accessor attributes
    :initform nil)
   (attributes-getter
    :accessor attributes-getter
    :initform #'get-attributes
    :initarg :attributes-getter)
   (attribute-slot-map
    :accessor attribute-slot-map
    :initform nil)
   (global-properties
    :initarg :global-properties
    :accessor global-properties
    :initform nil)
   (classes 
    :initarg :classes 
    :accessor classes 
    :initform nil)
   (use-instance-class-p 
    :initarg :use-instance-class-p 
    :accessor use-instance-class-p 
    :initform t)
   (initializedp :initform nil)
   (modifiedp :accessor modifiedp :initform nil :initarg :modifiedp)
   (modifications :accessor modifications :initform nil)))


(defmethod attributes :around ((self mewa))
  (let ((a (call-next-method)))
    (or a (funcall (attributes-getter self) self))))

(defgeneric get-attributes (mewa))

(defmethod get-attributes ((self mewa))
  (if (instance self)
  (append (meta-model:list-slots (instance self))
	  (meta-model:list-has-many (instance self)))
  nil))

(defmethod find-instance-classes ((self mewa))
  (mapcar #'class-name 
	  (it.bese.arnesi.mopp:compute-class-precedence-list (class-of (instance self)))))

(defun make-presentation-for-attribute-list-item
    (occurence att-name plist parent-presentation &optional type)
  (declare (type list plist) (type symbol att-name))
  "This is a ucw specific function that will eventually be factored elsewhere."
  (let* ((attribute (find-attribute occurence att-name))
	 (type (when attribute (or type (description.type attribute))))
	 (class-name 
	  (or (gethash (if (consp type)
			   (car type)
			   type)
		       *presentation-slot-type-mapping*) 
	      (error  "Can't find slot type for ~A in ~A from ~A" att-name occurence parent-presentation))))

    ;(warn "~%~% **** Making attribute ~A ~%~%" class-name)
   (cons (attribute.name attribute) (apply #'make-instance 
				   class-name
				   (append (plist-nunion
					    plist
					    (plist-union
					     (global-properties parent-presentation)
					     (description.properties attribute)))
					   (list :size 30 :parent parent-presentation))))))

(defmethod find-applicable-attributes-using-attribute-list (occurence attribute-list)
  "Returns a list of functions that, when called with an object presentation, 
returns the ucw slot presentation that will be used to present this attribute 
in that object presentation."
    (loop for att in attribute-list
	  with funs = (list)
	  do (let ((att att)) (cond 
	       ;;simple casee
	       ((symbolp att) 
		(push #'(lambda (p)
			  (make-presentation-for-attribute-list-item occurence att nil p))
		      funs))
	       ;;if the car is a keyword then this is an inline def
	       ;; drewc nov 12 2005:
	       ;; i never used this, and never told anybody about it.
	       ;; removing it.
	       #+ (or) ((and (listp x) (keywordp (car x)))
			(let ((att (apply #'make-attribute x)))
			  (setf (cddr att) 
				(plist-union (cddr att) (global-properties self)))
			  att))
	     
	       ;; if the plist has a :type	  
	       ((and (listp att) (getf (cdr att) :type))
		(let ((type (getf (cdr att) :type)))
		  (push #'(lambda (p)
			    (make-presentation-for-attribute-list-item
			     occurence (first att)
			     (cdr att)
			     p
			     type))
			funs)))
	       ;;finally if we are just overiding the props
	       ((and (listp att) (symbolp (car att)))
		(push #'(lambda (p)
			  (make-presentation-for-attribute-list-item occurence (first att) (rest att) p))
		      funs))))
	  finally (return (nreverse funs))))


(defun find-attribute-names (mewa)
  (mapcar #'(lambda (x)
	      (if (listp x)
		  (first x)
		  x))
	  (attributes mewa)))

(defmethod find-applicable-attributes ((self mewa))
  (if (attributes self)
      (find-applicable-attributes-using-attribute-list (instance self) (attributes self))
      (find-applicable-attributes-using-attribute-list (instance (get-attributes self)))))


(defmethod find-slot-presentations ((self mewa))
  (mapcar #'(lambda (a) (funcall a self))
	  (find-applicable-attributes self)))

(defmethod find-attribute-slot ((self mewa) (attribute symbol))
  (cdr (assoc attribute (attribute-slot-map self))))

(defmethod initialize-slots ((self mewa))
  (when (instance self)
    (when (use-instance-class-p self)
      (setf (classes self) 
	    (append (find-instance-classes self)
		    (classes self))))
    (setf (attribute-slot-map self) (find-slot-presentations self))
    (setf (slots self) (mapcar #'(lambda (x)(cdr x)) (attribute-slot-map self )))))


(defmethod make-presentation ((object t) &key (type :viewer) (initargs nil))
  (warn "making old-style for ~A ~A ~A" object type initargs)
  ;(warn "Initargs : ~A" initargs)
  (let* ((a (find-attribute object type))
	 (d-a (when a (find-display-attribute (occurence a) (description.type (occurence  a)))))
	 (i (apply #'make-instance
		   (if d-a 
		       (find-old-type (description.type a))
		       type) 
		   (plist-union initargs (when a
					   (description.properties a))))))
    (warn "attribute? ~A ~A " (and a (description.type  (find-attribute object type)) ) 					   (description.properties a))
    (setf (slot-value i 'instance) object)
    (initialize-slots i)
    (setf (slot-value i 'initializedp) t)
    i))

(defmethod make-presentation ((list list) &key (type :listing) (initargs nil))  
  (let ((args (append
	       `(:type ,type) 
	       `(:initargs 
		 (:instances ,list
		  ,@initargs)))))
    
    (apply #'make-presentation (car list) args)))

(defmethod initialize-slots-place ((place ucw::place) (mewa mewa))
  (setf (slots mewa) (mapcar #'(lambda (x) 
			       (prog1 x 
				 (setf (component.place x) place)))
                            (slots mewa))))
  
(arnesi:defmethod/cc call-component :before ((from standard-component) (to mewa))
  (unless (slot-value to 'initializedp)
    (initialize-slots to))
  (setf (slot-value to 'initializedp) t)
  (initialize-slots-place (component.place from) to)
  to)



(defmacro call-presentation (object &rest args)
  `(present-object ,object :presentation (make-presentation ,object ,@args)))


(defcomponent about-dialog (option-dialog)
  ((body :initarg :body)))

(defmethod render-on ((res response) (self about-dialog))
  (call-next-method)
  (render-on res (slot-value self 'body)))


(defaction cancel-save-instance ((self mewa))
  (cond  
    ((meta-model::persistentp (instance self))
      (meta-model::update-instance-from-records (instance self))
      (answer self))
    (t (answer nil))))

(defaction save-instance ((self mewa))
  (meta-model:sync-instance (instance self))
  (setf (modifiedp self) nil)
  (answer self))

(defmethod confirm-sync-instance ((self mewa))
  nil)

(defaction ensure-instance-sync ((self mewa))
  (when (modifiedp self)
    (if nil
	(let ((message (format nil "Record has been modified, Do you wish to save the changes?")))
	  (case (call 'about-dialog
		      :body (make-presentation (instance self) 
					       :type :viewer)
		      :message message
		      :options '((:save . "Save changes to Database")
				 (:cancel . "Cancel all changes")))
	    (:cancel
	     (cancel-save-instance self))
	    (:save 
	     (save-instance self))))
	(save-instance self))))

(defaction sync-and-answer ((self mewa))
  (ensure-instance-sync self)
  (answer (instance self)))

(defaction ok ((self mewa) &optional arg)
  "Returns the component if it has not been modified. if it has been, prompt user to save or cancel"
  ;(declare (ignore arg))
  (sync-and-answer self))

(defmethod (setf presentation-slot-value) :around (value (slot slot-presentation) instance)
  (let* ((old (prog1 
		 (presentation-slot-value slot instance)
	       (call-next-method)))
	(new (presentation-slot-value slot instance)))
  
  (unless (equal new old )
    (let ((self (ucw::parent slot)))
      (setf (modifiedp self) instance
	    (modifications self)  (append (list new old value slot instance) (modifications self)))))))







;; This software is Copyright (c) Drew Crampsie, 2004-2005.
;; You are granted the rights to distribute
;; and use this software as governed by the terms
;; of the Lisp Lesser GNU Public License
;; (http://opensource.franz.com/preamble.html),
;; known as the LLGPL.
