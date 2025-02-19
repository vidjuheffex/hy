(import
  itertools
  sys
  types
  contextlib [contextmanager]

  pytest)

(with-decorator
  contextmanager
  (defn temp-module [module-name]
    (let [module (types.ModuleType module-name)
          old-module (sys.modules.get module-name)]
      (setv (get sys.modules module-name) module)
      (try
        (yield module)
        (finally
          (if old-module
              (setv (get sys.modules module-name) module)
              (sys.modules.pop module-name)))))))


(defn eval-isolated [tree [module None]]
  (if module
      (hy.eval tree :locals {} :module module)
      (with [module (temp-module "<test>")]
        (hy.eval tree :locals {} :module module))))

(defn eval-module [s]
  (eval-isolated (hy.read-module s)))

(defn test-reader-macros []
  (assert (= (eval-module #[[(defreader foo '1) #foo]]) 1))
  (assert (in (hy.mangle "#foo")
    (eval-module #[[(defreader foo '1) __reader_macros__]])))

  ;; Assert reader macros operating exclusively at read time
  (with [module (temp-module "<test>")]
    (setv it (hy.read-many #[reader[
                              (defreader lower
                                (hy.models.String
                                  (.lower (&reader.parse-one-form))))
                              #lower "HeLLO, WoRLd!"
                           ]reader]))
    (eval-isolated (next it) module)
    (assert (= (next it) '"hello, world!"))))

(defn test-require-readers []
  (with [module (temp-module "<test>")]
    (setv it (hy.read-many #[[(require tests.resources.tlib :readers [upper])
                             #upper hello]]))
    (eval-isolated (next it) module)
    (assert (= (next it) 'HELLO)))

  ;; test require :readers & :macros is order independent
  (for [s ["[qplah] :readers [upper]"
           ":readers [upper] [qplah]"
           ":macros [qplah] :readers [upper]"
           ":readers [upper] :macros [qplah]"]]
    (assert (=
      (eval-module #[f[
        (require tests.resources.tlib {s})
        [(qplah 1) #upper "hello"]]f])
      [[8 1] "HELLO"])))

  ;; test can't redefine :macros or :readers assignment brackets
  (with [(pytest.raises hy.errors.HySyntaxError)]
    (eval-module #[[(require tests.resources.tlib [taggart] [upper])]]))
  (with [(pytest.raises hy.errors.HySyntaxError)]
    (eval-module #[[(require tests.resources.tlib :readers [taggart] :readers [upper])]])))
