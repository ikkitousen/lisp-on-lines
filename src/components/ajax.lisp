(in-package :lisp-on-lines)

;;;; for when there is nothing left to display.
(defcomponent empty-page (window-component)
  ())

(defmethod render-on ((res response) (self empty-page))
  "didnt find a thing")

(defcomponent auto-complete ()
  ((input-id :accessor input-id :initform (arnesi:random-string 10 arnesi:+ascii-alphabet+))
   (output-id :accessor output-id :initform (arnesi:random-string 10 arnesi:+ascii-alphabet+))
   (client-value 
    :accessor client-value 
    :initform "" 
    :documentation "The string the user has, so far, insterted.")
   (index 
    :accessor index 
    :initform nil 
    :documentation "The index (for use with NTH) in list-of-values of the item selected via Ajax")
   (list-of-values 
    :accessor list-of-values 
    :initform '() 
    :documentation "The list generated by values-generator")
   (values-generator :accessor values-generator :initarg :values-generator
                     :documentation "Function which, when passed the auto-complete component, returns a list of objects.")
   (value 
    :accessor value
    :initform nil
    :documentation  "The lisp value of the object selecting in the drop down")
   (as-value :accessor as-value :initarg :as-value
             :documentation "Function which, when passed a value, returns the string to put in the text box.")
   (render-it :accessor render-it :initarg :render
           :documentation "Function which, when passed the component and one of the values render it (the value).")
   (input-size :accessor input-size :initarg :input-size :initform 20)
   (submit-on-select-p 
    :accessor submit-on-select-p 
    :initarg :submit-on-select-p 
    :initform t)
   (output-component-name :accessor output-component-name :initarg :output-comonent-name :initform 'auto-complete-output)))

(defmethod js-on-complete ((l auto-complete))
  `(lambda (transport) 
    (setf (slot-value (document.get-element-by-id ,(output-id l)) 
	   'inner-h-t-m-l)
     transport.response-text)))

(defmacro make-action-url (component action)
  "
There has got to be something like this buried in UCW somewhere, 
but here's what i use."
  `(ucw::print-uri-to-string
    (compute-url ,component 
     :action-id (ucw::make-new-action (ucw::context.current-frame *context*)
		 (lambda ()
		   (arnesi:with-call/cc
		     ,action))))))

(defun generate-ajax-request (js-url &optional js-options)
  `(new 
    (*Ajax.*Request 
     ,js-url 
     ,js-options)))

(defmacro with-ajax-request (js-url &rest js-options)
  `(generate-ajax-request-for-url 
    ,js-url
    ,@js-options))
  
(defmacro with-ajax-action ((component) &body action)
  `(generate-ajax-request
    (make-action-url ,component (progn ,@action)))) 
	

(defun make-auto-complete-url (input-id)
  "creates a url that calls the auto-complete entry-point for INPUT-ID."
  (format nil "auto-complete.ucw?&auto-complete-id=~A&~A=~A" 
	  input-id  "session"  
	  (ucw::session.id (ucw::context.session ucw::*context*))))

(defaction on-submit ((l auto-complete))
  ())

(defmethod js-on-select ((l auto-complete))
  "the javascript that is called when an item is selected"
  (when (submit-on-select-p l)
    `(progn
      (set-action-parameter ,(register-action
			      (lambda () 
				  (arnesi:with-call/cc 
				    (on-submit l)))))
      (submit-form))))
   

(defmethod render ( (l auto-complete))
  ;; session-values are stored in an eql hash table.
  (let ((input-key (intern (input-id l))))
    ;; We are storing the input components in the session,
    ;; keyed on the string that we also use as the id for 
    ;; the input field. 
    
    (unless (get-session-value input-key)
      (setf (get-session-value input-key) l))
    
    ;; A hidden field to hold the index number selected via javascript
    (<ucw:text :accessor (client-value l)
	       :id (input-id l) :size (input-size l))
    (<:div :id (output-id l) :class "auto-complete" (<:as-html " ")))
  (let* ((a (make-symbol (format nil "~A-autocompleter" (input-id l))))
	 (f (make-symbol (format nil "~A.select-entry-function"a))))
    (<ucw:script 
     `(setf ,a
       (new 
	(*Ajax.*Autocompleter 
	 ,(input-id l) ,(output-id l) 
	 ,(make-auto-complete-url (input-id l))
	 (create
	  :param-name "value"))))
     `(setf ,f (slot-value ,a 'select-entry))
     `(setf (slot-value ,a 'select-entry)
       (lambda () 
	 (,f)
	 ,(generate-ajax-request
	   (make-auto-complete-url (input-id l))
	   `(create 
	     :parameters (+ "&index=" (slot-value ,a 'index))
	     :method "post"
	     :on-complete (lambda (res)
			    ,(js-on-select l)))))))))
     

;;;; * auto-complete-ouput 


(defcomponent auto-complete-output (window-component)
  ((auto-complete :initarg :auto-complete :accessor auto-complete)))

(defmethod render ((output auto-complete-output))
  (let ((auto-complete (auto-complete output)))
    (setf (list-of-values auto-complete)
	  (funcall (values-generator auto-complete) (client-value auto-complete)))
    (<:ul 
     :class "auto-complete-list" 
     (arnesi:dolist* (value (list-of-values auto-complete))
       (<:li 
	:class "auto-complete-list-item"
	(funcall (render-it auto-complete) value))))
    (answer-component output t)))

(defcomponent fkey-auto-complete (auto-complete)
  ())

(defmethod js-on-select ((self fkey-auto-complete))
  (with-ajax-action (self)
    (mewa::sync-foreign-instance (ucw::parent self) (value self))))

(defslot-presentation ajax-foreign-key-slot-presentation (mewa::foreign-key-slot-presentation)
  ((original-value :accessor original-value :initform nil) 
   (search-slots :accessor search-slots :initarg :search-slots :initform nil)
   (live-search 
     :accessor live-search
     :component fkey-auto-complete))
  (:type-name ajax-foreign-key))


(defmethod shared-initialize :after ((slot ajax-foreign-key-slot-presentation) slots &rest args)
  (let* ((l (live-search slot))
	 (slot-name (slot-name slot))
	 (instance (instance (ucw::parent slot)))
	 (foreign-instance (explode-foreign-key instance slot-name))
	 (class-name (class-name
		      (class-of foreign-instance))))
    ;; If no search-slots than use the any slots of type string
    (unless (search-slots slot)
      (setf (search-slots slot) (find-slots-of-type foreign-instance)))

    (setf (lisp-on-lines::values-generator l) 
	  (lambda (input)
	    (word-search class-name  
			 (search-slots slot)  input)))
		    
    (setf (lisp-on-lines::render-it l)
	  (lambda (val) 
	    (<ucw:render-component 
	     :component (make-presentation val :type :one-line))))))
	  
(defaction revert-foreign-slot ((slot ajax-foreign-key-slot-presentation))
  (setf (lol::value (live-search slot)) nil)
  (when (original-value slot)
  (mewa::sync-foreign-instance slot (original-value slot))))

(defmethod present-slot :around ((slot ajax-foreign-key-slot-presentation) instance)

  (let ((foreign-instance 
	 (if (lol::value (live-search slot))
	     (lol::value (live-search slot))
	     (setf (original-value slot)
		   (when (presentation-slot-value slot instance) 
		     (meta-model:explode-foreign-key instance (slot-name slot)))))))
    
    (flet ((render-s () (when foreign-instance (call-next-method))))

      (if (slot-boundp slot 'ucw::place)
	  (cond 
	    ((editablep slot)
	     (when  foreign-instance
	       (setf (client-value (live-search slot))
		     (with-output-to-string (s)
		       (yaclml:with-yaclml-stream s 
			 (present (make-presentation foreign-instance
						     :type :one-line))))))
	    
	     (<ucw:render-component :component (live-search slot))
	     #+ (or) (<ucw:submit :action (revert-foreign-slot slot)
			  :value "Undo")
			      #+ (or) (<ucw:submit :action  (mewa::search-records slot instance) :value "find" :style "display:inline"))
	    ((mewa::linkedp slot)
	     (<ucw:a :action (mewa::view-instance slot foreign-instance) 
		     (render-s)))
	    (t       
	     (render-s)))
	  ;; presentation is used only for rendering
	  (render-s))))
)