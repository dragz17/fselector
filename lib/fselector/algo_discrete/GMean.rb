#
# FSelector: a Ruby gem for feature selection and ranking
#
module FSelector
#
# GMean (GM)
#
#     GM = sqrt(Sensitivity * Specificity)
#     
#                     TP * TN                   A * D
#        = sqrt(------------------) = sqrt(---------------)
#                (TP+FN) * (TN+FP)          (A+C) * (B+D)
#
  class GMean < BaseDiscrete
    # this algo outputs weight for each feature
    @algo_type = :feature_weighting
    
    private
    
    # calculate contribution of each feature (f) for each class (k)
    def calc_contribution(f)
      each_class do |k|
        a, b, c, d = get_A(f, k), get_B(f, k), get_C(f, k), get_D(f, k)
        
        s = 0.0
        x = (a+c)*(b+d)
        
        s = Math.sqrt( (a*d)/x ) if not x.zero?
        
        set_feature_score(f, k, s)
      end
    end # calc_contribution
    
    
  end # class
  
  
  # shortcut so that you can use FSelector::GM instead of FSelector::GMean
  GM = GMean
  
  
end # module
