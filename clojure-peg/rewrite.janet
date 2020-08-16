# QUESTIONS:
#
# XXX: capturing and storing location info has a cost (see
#      tests at end of experimental.janet).  what is an appropriate way?
#
# XXX: what is a good way to store location info?  suppose just byte
#      offsets are being used, one idea is to use the second position to
#      store a struct:
#
#        [:vector {:start 23 :end 10} [:keyword ":a"] ... ]
#
#      another idea is to use the second (and possibly some subsequent
#      positions):
#
#        [:vector 23 10 [:keyword ":a"] ... ]
#
#      the former seems more extensible and readable, while the latter
#      is likely more performant.
#
# XXX: byte offset seems like a more performant thing to capture
#      and store compared to line and column information.  line and
#      column info seem like extra processing with low return.  is that
#      sufficient?

(import ./grammar :prefix "")

(def cg-capture-ast
  # cg is a struct, need something mutable
  (let [ca (table ;(kvs cg))]
    # override things that need to be captured
    (each kwd [:character :comment :keyword :macro-keyword :number
               :string :symbol :whitespace]
          (put ca kwd
               ~(cmt (capture ,(in ca kwd))
                     ,|[kwd $])))
    (each kwd [:backtick :conditional :conditional-splicing
               :deprecated-metadata-entry :deref :discard
               :eval :metadata :metadata-entry :namespaced-map
               :quote :symbolic :tag :unquote :unquote-splicing :var-quote]
          (put ca kwd
               ~(cmt (capture ,(in ca kwd))
                     ,|[kwd ;(slice $& 0 -2)])))
    (each kwd [:list :map :set :vector]
          (put ca kwd
               (tuple # array needs to be converted
                 ;(put (array ;(in ca kwd))
                       2 ~(cmt (capture ,(get-in ca [kwd 2]))
                               ,|[kwd ;(slice $& 0 -2)])))))
    # finish up
    (-> ca
        #
        (put :auto-resolve
             ~(cmt (capture ,(in ca :auto-resolve))
                   ,(fn [_] [:auto-resolve])))
        #
        (put :regex
             (tuple
               ;(put (array ;(in ca :regex))
                     2 ~(cmt (capture ,(get-in ca [:regex 2]))
                             ,|[:regex (in $& 1)]))))
        #
        (put :fn
             (tuple
               ;(put (array ;(in ca :fn))
                     2 ~(cmt (capture ,(get-in ca [:fn 2]))
                             ,|[:fn (in $& 0)]))))
        # tried using a table with a peg but had a problem, so use a struct
        table/to-struct)))

(comment

  (peg/match cg-capture-ast " ")
  # => @[[:whitespace " "]]

  (peg/match cg-capture-ast "; hello")
  # => @[[:comment "; hello"]]

  (peg/match cg-capture-ast "a")
  # => @[[:symbol "a"]]

  (peg/match cg-capture-ast ":a")
  # => @[[:keyword ":a"]]

  (peg/match cg-capture-ast "(:a :b :c)")
  ``
  @[[:list
     [:keyword ":a"] [:whitespace " "]
     [:keyword ":b"] [:whitespace " "]
     [:keyword ":c"]]]
  ``

  (peg/match cg-capture-ast "[:a :b :c]")
  ``
  @[[:vector
     [:keyword ":a"] [:whitespace " "]
     [:keyword ":b"] [:whitespace " "]
     [:keyword ":c"]]]
  ``

  (peg/match cg-capture-ast "{:a 1 :b 2}")
  ``
  @[[:map
     [:keyword ":a"] [:whitespace " "]
     [:number "1"] [:whitespace " "]
     [:keyword ":b"] [:whitespace " "]
     [:number "2"]]]
  ``

  (peg/match cg-capture-ast "#{:a :b :c}")
  ``
  @[[:set
     [:keyword ":a"] [:whitespace " "]
     [:keyword ":b"] [:whitespace " "]
     [:keyword ":c"]]]
  ``

  (peg/match cg-capture-ast "\"a\"")
  # => @[[:string "\"a\""]]

  (peg/match cg-capture-ast "#\".\"")
  # => @[[:regex "\".\""]]

  (peg/match cg-capture-ast "#(inc %)")
  ``
  @[[:fn
     [:list
      [:symbol "inc"] [:whitespace " "]
      [:symbol "%"]]]]
  ``

  (peg/match cg-capture-ast "#::a{}")
  # => @[[:namespaced-map [:macro-keyword "::a"] [:map]]]

  (peg/match cg-capture-ast "#::{}")
  # => @[[:namespaced-map [:auto-resolve] [:map]]]

  (peg/match cg-capture-ast "#:a{}")
  # => @[[:namespaced-map [:keyword ":a"] [:map]]]

  (peg/match cg-capture-ast "#=a")
  # => @[[:eval [:symbol "a"]]]

  (peg/match cg-capture-ast "#= a")
  # => @[[:eval [:whitespace " "] [:symbol "a"]]]

  (peg/match cg-capture-ast "#=(+ a b)")
  ``
  @[[:eval
     [:list
      [:symbol "+"] [:whitespace " "]
      [:symbol "a"] [:whitespace " "]
      [:symbol "b"]]]]
  ``

  (peg/match cg-capture-ast "##Inf")
  # => @[[:symbolic [:symbol "Inf"]]]

  (peg/match cg-capture-ast "## NaN")
  # => @[[:symbolic [:whitespace " "] [:symbol "NaN"]]]

  (peg/match cg-capture-ast "#'a")
  # => @[[:var-quote [:symbol "a"]]]

  (peg/match cg-capture-ast "\\newline")
  # => @[[:character "\\newline"]]

  (peg/match cg-capture-ast "\\ua08e")
  # => @[[:character "\\ua08e"]]

  (peg/match cg-capture-ast "\\a")
  # => @[[:character "\\a"]]

  (peg/match cg-capture-ast "@a")
  # => @[[:deref [:symbol "a"]]]

  (peg/match cg-capture-ast "'a")
  # => @[[:quote [:symbol "a"]]]

  (peg/match cg-capture-ast "`a")
  # => @[[:backtick [:symbol "a"]]]

  (peg/match cg-capture-ast "~a")
  # => @[[:unquote [:symbol "a"]]]

  (peg/match cg-capture-ast "~(:a :b :c)")
  ``
  @[[:unquote
     [:list
      [:keyword ":a"] [:whitespace " "]
      [:keyword ":b"] [:whitespace " "]
      [:keyword ":c"]]]]
  ``

  (peg/match cg-capture-ast "~@(:a :b :c)")
  ``
  @[[:unquote-splicing
     [:list
      [:keyword ":a"] [:whitespace " "]
      [:keyword ":b"] [:whitespace " "]
      [:keyword ":c"]]]]
  ``

  (peg/match cg-capture-ast "1")
  # => @[[:number "1"]]

  (peg/match cg-capture-ast "^{:a true} [:a]")
  ``
  @[[:metadata
     [:metadata-entry
      [:map
       [:keyword ":a"] [:whitespace " "]
       [:symbol "true"]]]
     [:whitespace " "]
     [:vector
      [:keyword ":a"]]]]
  ``

  (peg/match cg-capture-ast "#^{:a true} [:a]")
  ``
  @[[:metadata
     [:deprecated-metadata-entry
      [:map
       [:keyword ":a"] [:whitespace " "]
       [:symbol "true"]]]
     [:whitespace " "]
     [:vector
      [:keyword ":a"]]]]
  ``

  (peg/match cg-capture-ast "#uuid \"00000000-0000-0000-0000-000000000000\"")
  ``
  @[[:tag
     [:symbol "uuid"] [:whitespace " "]
     [:string "\"00000000-0000-0000-0000-000000000000\""]]]
  ``

  (peg/match cg-capture-ast "#?(:clj 0 :cljr 1)")
  ``
  @[[:conditional
     [:list
      [:keyword ":clj"] [:whitespace " "]
      [:number "0"] [:whitespace " "]
      [:keyword ":cljr"] [:whitespace " "]
      [:number "1"]]]]
  ``

  (peg/match cg-capture-ast "#?@(:clj [0 1] :cljr [8 9])")
  ``
  @[[:conditional-splicing
     [:list
      [:keyword ":clj"] [:whitespace " "]
      [:vector
       [:number "0"] [:whitespace " "]
       [:number "1"]] [:whitespace " "]
      [:keyword ":cljr"] [:whitespace " "]
      [:vector
       [:number "8"] [:whitespace " "]
       [:number "9"]]]]]
  ``

  (peg/match cg-capture-ast "#_ a")
  # => @[[:discard [:whitespace " "] [:symbol "a"]]]

  (peg/match cg-capture-ast "#_ #_ :a :b")
  `` @[[:discard
        [:whitespace " "]
        [:discard
         [:whitespace " "] [:keyword ":a"]]
        [:whitespace " "]
        [:keyword ":b"]]]
  ``

  )

(defn ast
  [src]
  (if-let [parsed (peg/match cg-capture-ast src)]
    (array/insert parsed 0 :code)
    [:code]))

(comment

  (ast "(+ 1 1)")
  ``
  '@[:code
     (:list
      (:symbol "+") (:whitespace " ")
      (:number "1") (:whitespace " ")
      (:number "1"))]
  ``

  (ast "")
  # => [:code]

  )

(defn code*
  [ast buf]
  (case (first ast)
    :code
    (each elt (drop 1 ast)
          (code* elt buf))
    #
    :character
    (buffer/push-string buf (in ast 1))
    :comment
    (buffer/push-string buf (in ast 1))
    :keyword
    (buffer/push-string buf (in ast 1))
    :macro-keyword
    (buffer/push-string buf (in ast 1))
    :number
    (buffer/push-string buf (in ast 1))
    :string
    (buffer/push-string buf (in ast 1))
    :symbol
    (buffer/push-string buf (in ast 1))
    :whitespace
    (buffer/push-string buf (in ast 1))
    #
    :list
    (do
      (buffer/push-string buf "(")
      (each elt (drop 1 ast)
            (code* elt buf))
      (buffer/push-string buf ")"))
    :map
    (do
      (buffer/push-string buf "{")
      (each elt (drop 1 ast)
            (code* elt buf))
      (buffer/push-string buf "}"))
    :set
    (do
      (buffer/push-string buf "#{")
      (each elt (drop 1 ast)
            (code* elt buf))
      (buffer/push-string buf "}"))
    :vector
    (do
      (buffer/push-string buf "[")
      (each elt (drop 1 ast)
            (code* elt buf))
      (buffer/push-string buf "]"))
    #
    :namespaced-map
    (do
      (buffer/push-string buf "#")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :quote
    (do
      (buffer/push-string buf "'")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :fn
    (do
      (buffer/push-string buf "#")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :deref
    (do
      (buffer/push-string buf "@")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :backtick
    (do
      (buffer/push-string buf "`")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :unquote
    (do
      (buffer/push-string buf "~")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :unquote-splicing
    (do
      (buffer/push-string buf "~@")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :discard
    (do
      (buffer/push-string buf "#_")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :var-quote
    (do
      (buffer/push-string buf "#'")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :metadata-entry
    (do
      (buffer/push-string buf "^")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :deprecated-metadata-entry
    (do
      (buffer/push-string buf "#^")
      (each elt (drop 1 ast)
            (code* elt buf)))
    #
    :symbolic
    (do
      (buffer/push-string buf "##")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :tag
    (do
      (buffer/push-string buf "#")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :conditional
    (do
      (buffer/push-string buf "#?")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :conditional-splicing
    (do
      (buffer/push-string buf "#?@")
      (each elt (drop 1 ast)
            (code* elt buf)))
    :eval
    (do
      (buffer/push-string buf "#=")
      (each elt (drop 1 ast)
            (code* elt buf)))
    #
    :metadata
    (do
      (each elt (tuple/slice ast 1 -2)
            (code* elt buf))
      (code* (last ast) buf))
    #
    :regex
    (do
      (buffer/push-string buf "#")
      (buffer/push-string buf (in ast 1)))
    #
    :auto-resolve
    (buffer/push-string buf "::")
    ))

(defn code
  [ast]
  (let [buf @""]
    (code* ast buf)
    (string buf)))

(comment

  (code [:code [:keyword ":a"]])
  # => ":a"

  (code [:code [:number "1"]])
  # => "1"

  (code [:code [:whitespace " "]])
  # => " "

  (code [:code
         [:list
          [:number "1"] [:whitespace " "]
          [:number "2"]]])
  # => "(1 2)"

  (code [:code
         [:map
          [:keyword ":a"] [:whitespace " "]
          [:number "1"]]])
  # => "{:a 1}"

  (code [:code
         [:vector
          [:number "1"] [:whitespace " "]
          [:number "2"]]])
  # => "[1 2]"

  (code [:code
         [:set
          [:number "1"] [:whitespace " "]
          [:number "2"]]])
  # => "#{1 2}"

  (code [:code [:character "\\newline"]])
  # => "\\newline"

  (code [:code [:comment ";; hi"]])
  # => ";; hi"

  (code [:code [:string "\"smile\""]])
  # => "\"smile\""

  (code [:code [:symbol "a"]])
  # => "a"

  (code [:code [:regex "\".\""]])
  # => "#\".\""

  (code [:code [:quote [:symbol "a"]]])
  # => "'a"

  (code [:code
         [:quote
          [:list
           [:keyword ":a"]]]])
  # => "'(:a)"

  (code [:code
         [:fn
          [:list
           [:symbol "inc"] [:whitespace " "]
           [:symbol "%"]]]])
  # => "#(inc %)"

  (code [:code [:deref [:symbol "a"]]])
  # => "@a"

  (code [:code
         [:deref
          [:list
           [:symbol "atom"] [:whitespace " "]
           [:symbol "nil"]]]])
  # => "@(atom nil)"

  (code [:code [:backtick [:symbol "a"]]])
  # => "`a"

  (code [:code [:unquote [:symbol "a"]]])
  # => "~a"

  (code [:code [:unquote-splicing [:symbol "a"]]])
  # => "~@a"

  (code [:code
         [:discard
          [:whitespace " "] [:symbol "a"]]])
  # => "#_ a"

  (code [:code [:var-quote [:symbol "a"]]])
  # => "#'a"

  (code [:code
         [:tag
          [:symbol "uuid"] [:whitespace " "]
          [:string "\"00000000-0000-0000-0000-000000000000\""]]])
  # => "#uuid \"00000000-0000-0000-0000-000000000000\""

  (code [:code [:metadata
                [:metadata-entry
                 [:map
                  [:keyword ":a"] [:whitespace " "]
                  [:symbol "true"]]]
                [:whitespace " "]
                [:vector
                 [:keyword ":a"]]]])
  # => "^{:a true} [:a]"

  (code [:code [:metadata
                [:deprecated-metadata-entry
                 [:map
                  [:keyword ":a"] [:whitespace " "]
                  [:symbol "true"]]]
                [:whitespace " "]
                [:vector
                 [:keyword ":a"]]]])
  # => "#^{:a true} [:a]"

  (code [:code
         [:namespaced-map
          [:macro-keyword "::a"]
          [:map]]])
  # => "#::a{}"

  (code [:code
         [:namespaced-map
          [:auto-resolve]
          [:map]]])
  # => "#::{}"

  (code [:code
         [:namespaced-map
          [:keyword ":a"]
          [:map]]])
  # => "#:a{}"

  (code [:code [:macro-keyword "::a"]])
  # => "::a"

  (code [:code [:symbolic [:symbol "Inf"]]])
  # => "##Inf"

  (code [:code
         [:symbolic
          [:whitespace " "]
          [:symbol "NaN"]]])
  # => "## NaN"

  (code [:code
         [:conditional
          [:list
           [:keyword ":clj"] [:whitespace " "]
           [:number "0"] [:whitespace " "]
           [:keyword ":cljr"] [:whitespace " "]
           [:number "1"]]]])
  # => "#?(:clj 0 :cljr 1)"

  (code [:code
          [:conditional-splicing
           [:list
            [:keyword ":clj"] [:whitespace " "]
            [:vector
             [:number "0"] [:whitespace " "]
             [:number "1"]] [:whitespace " "]
            [:keyword ":cljr"] [:whitespace " "]
            [:vector
             [:number "8"] [:whitespace " "]
             [:number "9"]]]]])
  # => "#?@(:clj [0 1] :cljr [8 9])"

  (code [:code [:eval [:symbol "a"]]])
  # => "#=a"

  (code [:code
         [:eval
          [:list
           [:symbol "+"] [:whitespace " "]
           [:symbol "a"] [:whitespace " "]
           [:symbol "b"]]]])
  # => "#=(+ a b)"

  )

(comment

  (defn round-trip
    [src]
    # houston, we have a property :)
    (code (ast src)))

  (round-trip ":a")
  # => ":a"

  (round-trip "1")
  # => "1"

  (round-trip " ")
  # => " "

  (round-trip "(1 2)")
  # => "(1 2)"

  (round-trip "{:a 1}")
  # => "{:a 1}"

  (round-trip "[1 2]")
  # => "[1 2]"

  (round-trip "#{1 2}")
  # => "#{1 2}"

  (round-trip "\\newline")
  # => "\\newline"

  (round-trip ";; hi")
  # => ";; hi"

  (round-trip "\"smile\"")
  # => "\"smile\""

  (round-trip "a")
  # => "a"

  (round-trip "#\".\"")
  # => "#\".\""

  (round-trip "'a")
  # => "'a"

  (round-trip "'(:a)")
  # => "'(:a)"

  (round-trip "#(inc %)")
  # => "#(inc %)"

  (round-trip "@a")
  # => "@a"

  (round-trip "@(atom nil)")
  # => "@(atom nil)"

  (round-trip "`a")
  # => "`a"

  (round-trip "~a")
  # => "~a"

  (round-trip "~@a")
  # => "~@a"

  (round-trip "#_ a")
  # => "#_ a"

  (round-trip "#'a")
  # => "#'a"

  (round-trip "#uuid \"00000000-0000-0000-0000-000000000000\"")
  # => "#uuid \"00000000-0000-0000-0000-000000000000\""

  (round-trip "^{:a true} [:a]")
  # => "^{:a true} [:a]"

  (round-trip "#^{:a true} [:a]")
  # => "#^{:a true} [:a]"

  (round-trip "#::a{}")
  # => "#::a{}"

  (round-trip "#::{}")
  # => "#::{}"

  (round-trip "#:a{}")
  # => "#:a{}"

  (round-trip "::a")
  # => "::a"

  (round-trip "##Inf")
  # => "##Inf"

  (round-trip "#?(:clj 0 :cljr 1)")
  # => "#?(:clj 0 :cljr 1)"

  (round-trip "#?@(:clj [0 1] :cljr [8 9])")
  # => "#?@(:clj [0 1] :cljr [8 9])"

  (round-trip "#=a")
  # => "#=a"

  (round-trip "#=(+ a b)")
  # => "#=(+ a b)"

  )

(comment

  (comment

    (let [src (slurp (string (os/getenv "HOME")
                       "/src/clojure/src/clj/clojure/core.clj"))]
      (= (string src)
        (code (ast src))))

    # 73, 75 ms per
    (let [start (os/time)]
      (each i (range 1000)
            (let [src
                  (slurp (string (os/getenv "HOME")
                                 "/src/clojure/src/clj/clojure/core.clj"))]
              (= src
                 (code (ast src)))))
      (print (- (os/time) start)))

  )

)
