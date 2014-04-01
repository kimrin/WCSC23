fi = open("../fv.bin", "r")
const pc_on_sq_old = read( fi, Int16, pos_n, NumSQ)
const kkp_old = read( fi, Int16, kkp_end, NumSQ, NumSQ)
#println("type of pc_on_sq = ", typeof(pc_on_sq))
#println("type of kkp = ", typeof(kkp))
close(fi)

const pc_on_sq = pc_on_sq_old
kkp = kkp_old
# kkp = zeros(Int16,NumSQ,NumSQ,kkp_end)
# for i = 1:kkp_end
#     for j = 1:NumSQ
#         for k = 1:NumSQ
#             kkp[k,j,i] = kkp_old[i,j,k]
#         end
#     end
# end

# println("pc_on_sq[0,0] = ", pc_on_sq[1,1])
# println("pc_on_sq[0,1] = ", pc_on_sq[1,2])
# println("pc_on_sq[1,0] = ", pc_on_sq[2,1])
# println("pc_on_sq[1,1] = ", pc_on_sq[2,2])
# println("kkp[0,0,0] = ", kkp[1,1,1])
# println("kkp[0,0,1] = ", kkp[1,1,2])
# println("kkp[0,1,0] = ", kkp[1,2,1])
# println("kkp[0,1,1] = ", kkp[1,2,2])
