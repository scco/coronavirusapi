require 'linefit'

testdata_x = [1,2,3,4,5,6]
testdata_y = [1,1,1,1,2,2]

#testdata_x = [1,2,3,4,5,6]
#testdata_y = [1,1,2,2,3,4]
def get_info_for(xs, ys)
  y_log = ys.map {|y| Math.log((y>0 ? y : 1).to_f)}
  lineFit = LineFit.new
  lineFit.setData(xs.map{|x| x.to_f},y_log)
  logIntercept,logSlope = lineFit.coefficients
  doublingTime = Math.log(2.0)/logSlope
  { "logSlope":logSlope, "doublingTime":doublingTime }
end

puts get_info_for(testdata_x, testdata_y)

