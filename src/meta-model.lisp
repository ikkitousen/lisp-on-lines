(in-package :meta-model)

(defvar *meta-models* (make-hash-table))

(defclass meta-model-class ()
  ((name
    :accessor meta-model.name
    :initarg :name
    :initform nil)
   (slots
    :accessor meta-model.slots
    :initarg :slots
    :initform nil)
   (superclasses
    :accessor meta-model.superclasses
    :initarg :superclasses
    :initform nil)
   (options
    :accessor meta-model.options
    :initarg :options
    :initform nil)   
   (metadata
    :accessor meta-model.metadata
    :initarg :metadata
    :initform nil)
   (instance
    :accessor meta-model.instance
    :initarg :instance
    :initform nil)
   (base-type
    :accessor meta-model.base-type
    :initarg :base-type
    :initform :clsql)))

(defmethod meta-model.metadata ((self (eql nil)))
  nil)

(defmethod meta-model.metadata ((self symbol))
  (meta-model.metadata (gethash self *meta-models*)))

(defmethod meta-model.metadata ((self standard-object))
  (meta-model.metadata (class-name (class-of self))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmethod make-meta-model (name supers slots options)
  (let ((m (make-instance 'meta-model-class 
			  :name name
			  :superclasses supers
			  :slots slots
			  :options options
			  ;; TODO : the metadata should inherit any superclasses
			  :metadata slots)))
    (setf (gethash name *meta-models*) m))))
	
(defmacro define-meta-model (name supers slots &rest options)
  `(make-meta-model ',name ',supers ',slots ',options))

(defgeneric generate-base-class-definition (base-type model name args))

(defmethod generate-base-class-expander ((model t) name args)
  (generate-base-class-definition (meta-model.base-type model) model name args))


(defmethod view-class-metadata ((model t))
  "
This is what meta-model.metadata used to be called,
most of the below functions expect this method to exist"
  (meta-model.metadata model))

(defun list-item-helper (type view &key (ret-fun #'car))
  "A helper function for the LIST-* methods"
   (remove nil
	   (mapcar #'(lambda (slot)
			  (let ((ret-val (funcall ret-fun slot))
				(kind (getf (cdr slot) :db-kind)))
			    (when (eql kind type)
			      ret-val )))
		   (view-class-metadata view))))

(defmethod list-join-attributes ((view t))
  "Returns all slots as an alist of (SLOT-NAME JOIN-ATTRIBUTES) where J-A is the contents of the :JOIN-CLASS portion of a slot definition"
  (remove nil (mapcar #'(lambda (def)(cons (car def) (getf (cdr def) :db-info ))) (view-class-metadata view))))

(defun list-relations-helper (view predicate-method &key (test-key :home-key) (return-key :join-class) (return-full nil))
  "A helper function for the listing join, relations and the like"
  (remove nil (mapcar #'(lambda (x)
	      (when (funcall predicate-method view (getf (cdr x) test-key ))
		(if return-full
		    x
		(getf (cdr x) return-key ))))
	  (list-join-attributes view))))

(defmethod list-slots ((view t))
  "list the non-joined slots of VIEW-CLASS"
  (remove-if #'(lambda (x) (find x (list-joins view)))
	     (append (list-item-helper :key view)
		     (list-item-helper nil view)
		     (list-item-helper :base view))))

(defmethod list-slot-types ((view t))
  "Returns an alist of (slot-name slot-type) where SLOT-TYPE is the CLSQL type"
  (labels  ((rfun (slot)
	      (cons (car slot)
		    (list (getf (cdr slot):type))))
  	    (lister (type)
	      (list-item-helper
	       type view
	       :ret-fun #'rfun)))
    (append (lister :key) (lister :base) (lister nil))))
			 
(defmethod slot-type ((view t) slot)
  "returns the CLSQL type of SLOT"
  (second (assoc slot (list-slot-types view))))
  
(defmethod list-joins ((view t))
  "lists slots that represent joins"
  (list-item-helper :join view))

(defmethod list-keys ((view t))
  "lists slots marked as :key"
  (list-item-helper :key view))

(defmethod primary-key-p ((view t) slot)
  "returns slot if it is primary key (NOTE: Currently this returns T if the slot appears in LIST_KEYS and does not take into account the :primary-key option. b0rked, to be sure"
  (find slot (list-keys view)))

(defmethod list-foreign-keys ((view t))
  "returns a list of FOREIGN-KEYS"
  (flet ((my-primary-key-p (slot)
	   (primary-key-p view slot)))
    (remove nil (remove-if #'my-primary-key-p
	       (mapcar #'(lambda (def)
			   (getf (cdr def) :home-key))
		       (list-join-attributes view))))))

(defmethod foreign-key-p ((view t) slot)
  "returns SLOT if it's a foreign key, nil otherwise"
  (find slot (list-foreign-keys view)))



(defmethod list-has-a ((view t))
  "returns a list of view-classes that are in a 1:1 relationship with VIEW"
  (list-relations-helper view #'foreign-key-p))

(defmethod list-has-many ((view t))
  "returns a list of view-classes that are in a 1:Many relationship with VIEW" 
  (mapcar #'car
	  (remove-if #'(lambda (x) (getf (cdr x) :target-slot))
		     (list-relations-helper
		      view
		      #'primary-key-p :return-full t))))

(defmethod list-many-to-many ((view t))
  "returns a list of view-classes that are in a Many:Many relationship with VIEW" 
  (mapcar #'car (list-relations-helper
		 view
		 #'(lambda (c a)
		     (declare (ignore c))a)
		 :test-key :target-slot
		 :return-full t)))

(defmethod explode-foreign-key ((model clsql:standard-db-object) slot &key (createp t))
  "returns the clsql view-class joined on SLOT"
  (dolist (s (list-join-attributes model))
    (when (equal (getf (cdr s) :home-key) slot)
      (let* ((fkey (getf (cdr s) :foreign-key))
	     (new (sync-instance (make-instance (getf (cdr s) :join-class))))
	     (val (or (slot-value model (car s))
		      (progn
			(when createp
			  (setf
			   (slot-value model slot)
			   (slot-value new fkey))
			  (sync-instance model)
			  (slot-value model (car s)))))))
	    
	(return-from explode-foreign-key 
	  (values val fkey))))))

(defun find-join-helper (foreign-key)
  (lambda (class slot) 
    (declare (ignore class))
    (when (equal slot foreign-key) t)))

(defmethod find-join-class ((view t) foreign-key)
  "Returns the VIEW-CLASS that is joined to VIEW via FOREGN-KEY"
  (car (list-relations-helper view (find-join-helper foreign-key) )))

(defmethod find-join-key ((view t) foreign-key)
  "returns the SLOT in the foreign VIEW-CLASS that joins with FOREIGN-KEY"
  (car (list-relations-helper view (find-join-helper foreign-key) :return-key :foreign-key)))

(defmethod explode-has-many ((view t) join-slot)
  "returns the class of the join as the primary value, the second and third value is the home key and the foreign key"
  (let ((att (assoc join-slot (list-join-attributes view))))
    (values (getf (cdr att) :join-class) 
	    (getf (cdr att) :home-key) 
	    (getf (cdr att) :foreign-key))))
  
(defgeneric expr-= (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-> (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-< (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-ends-with (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-starts-with (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-contains (instance slot-name value)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-and (instance &rest args)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-or (instance &rest args)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric expr-not (instance &rest args)
  (:documentation "Create search expression for appropriate backend."))

(defgeneric select-instances (instance &rest args)
  (:documentation "Select instances in backend dependent way"))

(defgeneric prepare-slot-name-for-select (instance slot-name)
  (:method (i s) s))

(defmacro def-compare-expr (instance-type name expr &key value-format)
  `(defmethod ,name ((instance ,instance-type) slot-name value)
     (declare (ignore instance))
     (,expr (prepare-slot-name-for-select instance slot-name) ,(typecase value-format
                                 (null 'value)
                                 (string `(format nil ,value-format value))
                                 (t `(,value-format value))))))


(defmacro def-logical-expr (instance-type name expr)
  `(defmethod ,name ((instance ,instance-type) &rest args)
     (declare (ignore instance))
     (apply ,expr args)))