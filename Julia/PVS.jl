const NULLMOVE_REDUCTION=2.0
const MAXTHINKINGTIME=(1000000000*18) # n sec

const TT_EXACT = 1
const TT_ALPHA = 2
const TT_BETA  = 3
const TT_INVALID = -1

immutable type TTKEY
    square::Array{Int,1} # incrementally updated, this array is usefull if we want to
    WhitePiecesInHands::Array{Int,1}
    BlackPiecesInHands::Array{Int,1}
    nextMove::Int # SENTE or GOTE    
end

function tt_probe(depth::Float64, alpha::Int, beta::Int, gs::GameStatus)
    val::Int = TT_INVALID
    best::Move = Move(0,0,0,0,0,0)
    key = TTKEY(gs.board.square, gs.board.WhitePiecesInHands, gs.board.BlackPiecesInHands, gs.board.nextMove)
    contents = get( gs.tt, hash(key), -1)
    fl::Int = TT_INVALID
    
    if contents != -1
        # match!
        best = contents.best

        if contents.depth >= depth
            if contents.flags == TT_EXACT
                val = contents.val
                fl = TT_EXACT
            end
            if (contents.flags == TT_ALPHA)&&(contents.val <= alpha)
                val = alpha
                fl = TT_ALPHA
            end
            if (contents.flags == TT_BETA)&&(contents.val >= beta)
                val = beta
                fl = TT_BETA
            end
        end
    end
    return val, best, fl
end

function tt_save(depth::Float64, val::Int, flags::Int, best::Move, gs::GameStatus)
    key = TTKEY(gs.board.square, gs.board.WhitePiecesInHands, gs.board.BlackPiecesInHands, gs.board.nextMove)
    contents = get( gs.tt, hash(key), -1)
    if contents != -1
        if contents.depth > depth
            return
        end
    end
    newcont = TransP(hash(key),best,depth,flags,val)
    gs.tt[hash(key)] = newcont
end

#@iprofile begin
function qsearch( gs::GameStatus, ply::Int, alpha::Int, beta::Int)
    # quiescence search
    val::Int = 0
    val2::Int = 0
    teban::Int = ((ply & 0x1) == 0)?gs.side:(gs.side$1)
    ev = (teban == SENTE)? 1: -1
    bestValue = -Infinity

    if gs.timedout
        return 0
    end
    gs.triangularLength[ply+1] = ply
    if in_check( teban, gs.board)
        return PVS( gs, ply, 1.0, alpha, beta,true)
    end
    val = ev * EvalBonanza( SENTE, gs.board, gs)

    if val >= beta
        return val
    end
    if val > alpha
        alpha = val
        bestValue = val
    end
    if (gs.inodes) & 1023 == 0
        now = time_ns()
        period::Int = now - gs.nsStart
        if period > MAXTHINKINGTIME
            gs.timedout = true
            return val
        end
    end
    if float(ply) > (gs.depth + 4.0) # changed!
        return alpha
    end

    gs.MoveBeginIndex = gs.moveBufLen[ply+1]
    gs.moveBufLen[ply+1+1] = generateQBB(gs.board, gs.moveBuf, teban, gs.moveBufLen[ply+1], gs)
    for i = gs.moveBufLen[ply+1]+1:gs.moveBufLen[ply+2]
        makeMove( gs.board, i, gs.moveBuf, teban)
        oote = in_check( teban, gs.board)
        if oote||(!oote && seeMoveFlag(gs.moveBuf[i]) == 0)
            #println("check!")
            takeBack( gs.board, i, gs.moveBuf, teban)
        else


	    gs.inodes += 1
	    val = -qsearch( gs, ply+1, -beta, -alpha)
            takeBack( gs.board, i, gs.moveBuf, teban)
            if bestValue < val
                # both sides want to maximize from *their* perspective
                gs.pvmovesfound += 1

                gs.triangularArray[ply+1,ply+1] = gs.moveBuf[i]
		# save this move
                for j = (ply +1+1):gs.triangularLength[ply+1+1]
                    gs.triangularArray[ply+1,j] = gs.triangularArray[ply+1+1,j]
                    # and append the latest best PV from deeper plies
                end
                gs.triangularLength[ply+1] = gs.triangularLength[ply + 1+1]
                rememberPV(gs)
            end
            bestValue=max(val,bestValue)
            alpha = max( alpha, val)
            if alpha >= beta
                return beta
            end
        end
    end
    bestValue
end

#end # @iprofile

function selectHash( gs::GameStatus, ply::Int, i::Int, depth::Float64, best::Move)
    # re-orders the move list so that the best move is selected as the next move to try.
    j::Int = 0
    k::Int = 0
    temp::Move = Move(0,0,0,0,0,0)

    for j = i:gs.moveBufLen[ply+1+1]
        if best.move == gs.moveBuf[j].move
            temp = gs.moveBuf[j]
	    gs.moveBuf[j] = gs.moveBuf[i]
	    gs.moveBuf[i] = temp
	    return
        end
    end
end

function selectmove( gs::GameStatus, ply::Int, i::Int, depth::Float64)
    # re-orders the move list so that the best move is selected as the next move to try.
    best::Int = 0
    j::Int = 0
    k::Int = 0
    temp::Move = Move(0,0,0,0,0,0)

    if gs.followpv && depth > 1.0
        for j = i:gs.moveBufLen[ply+1+1]
            if gs.moveBuf[j].move == gs.lastPV[ply+1].move
                temp = gs.moveBuf[j]
		gs.moveBuf[j] = gs.moveBuf[i]
		gs.moveBuf[i] = temp
		return
            end
        end
    end
    
    if gs.board.nextMove == GOTE
	best = gs.blackHeuristics[seeMoveFrom(gs.moveBuf[i])+1,seeMoveTo(gs.moveBuf[i])+1]
	j = i
	for k = (i + 1):gs.moveBufLen[ply+1+1]
            if gs.blackHeuristics[seeMoveFrom(gs.moveBuf[k])+1,seeMoveTo(gs.moveBuf[k])+1] > best
	        best = gs.blackHeuristics[seeMoveFrom(gs.moveBuf[k])+1,seeMoveTo(gs.moveBuf[k])+1]
                j = k
            end
        end
	if j > i
            temp = gs.moveBuf[j]
	    gs.moveBuf[j] = gs.moveBuf[i]
	    gs.moveBuf[i] = temp
        end
    else
	best = gs.whiteHeuristics[seeMoveFrom(gs.moveBuf[i])+1,seeMoveTo(gs.moveBuf[i])+1]
	j = i
	for k = (i + 1):gs.moveBufLen[ply+1+1]
            if gs.whiteHeuristics[seeMoveFrom(gs.moveBuf[k])+1,seeMoveTo(gs.moveBuf[k])+1] > best
	        best = gs.whiteHeuristics[seeMoveFrom(gs.moveBuf[k])+1,seeMoveTo(gs.moveBuf[k])+1]
                j = k
            end
        end
	if j > i
            temp = gs.moveBuf[j]
	    gs.moveBuf[j] = gs.moveBuf[i]
	    gs.moveBuf[i] = temp
        end
    end
end

#@iprofile begin
function PVS( gs::GameStatus, ply::Int, depth::Float64, alpha::Int, beta::Int, isID::Bool)
    movesfound::Int = 0
    gs.pvmovesfound = 0
    bestValue = -Infinity
    teban::Int = ((ply & 0x1) == 0)?gs.side:gs.side$1
    val::Int = 0
    tt_flag::Int = TT_ALPHA
    tt_val::Int = 0
    tt_bestMove = Move(0,0,0,0,0,0)
    gs.triangularLength[ply+1] = ply
    if (depth <= 0.0) 
	gs.followpv = false
        va::Int = qsearch(gs, ply, alpha, beta)
	return va
    end

    if (gs.inodes) & 1023 == 0
        now = time_ns()
        period::Int = now - gs.nsStart
        if period > MAXTHINKINGTIME
            gs.timedout = true
            return 0
        end
    end

    val, best, fl = tt_probe( depth, alpha, beta, gs)
    #if val != TT_INVALID
    #    return val
    #end
    # if fl == TT_EXACT
    #     return val
    # elseif fl == TT_ALPHA
    #     alpha = max(val,alpha)
    #     #return alpha
    # elseif fl == TT_BETA
    #     beta = min(beta,val)
    #     return beta
    # end
    
    if (!gs.followpv) && gs.allownull
        if true
            if in_check( teban, gs.board)
                gs.allownull = false
                gs.inodes += 1
                gs.board.nextMove $= 1
                val = -PVS( gs, ply, depth - NULLMOVE_REDUCTION, -beta, -beta+1,isID)
                gs.board.nextMove $= 1
                if gs.timedout
                    return 0
                end
                gs.allownull = true
                if val >= beta
                    return val
                end
            else
            end
        end
    end

    # IID
    if (!gs.followpv) && gs.allownull
        gs.allownull = false
        gs.inodes += 1
        gs.board.nextMove $= 1
        val = -PVS( gs, ply, depth - NULLMOVE_REDUCTION, -beta, -alpha,isID)
        gs.board.nextMove $= 1
        if gs.timedout
            return 0
        end
        gs.allownull = true
        if val >= beta
            return val
        end
    end
    ev = (teban == SENTE)? 1: -1
    tmpeval = ev * EvalBonanza( SENTE, gs.board, gs)

    if (!gs.followpv) && gs.allownull && depth < 3.0 && ((tmpeval - 100.0 * depth) >= beta)
        return tmpeval - 100.0*depth
    end

    gs.allownull = true
    # 0.5手延長うまくいかない。qsearchがPVSをも一回呼ぶため。
    movesfound = 0
    gs.pvmovesfound = 0
    gs.MoveBeginIndex = gs.moveBufLen[ply+1]
    gs.moveBufLen[ply+1+1] = generateBB(gs.board, gs.moveBuf, teban, gs.moveBufLen[ply+1], gs)

    beg = gs.moveBufLen[ply+1]+1
    for i = beg:gs.moveBufLen[ply+2]
        if (i == beg)&&(best.move != 0)
            selectHash( gs, ply, i, depth, best)
        else
            selectmove( gs, ply, i, depth)
        end
        makeMove( gs.board, i, gs.moveBuf, teban)
        ext::Float64 = 0.0
        #if i == beg
        #    ext = 0.5
        #end
        if in_check( teban, gs.board)
            #println("check!")
            takeBack( gs.board, i, gs.moveBuf, teban)
        else
	    gs.inodes += 1
	    movesfound += 1

	    if i > beg
                val = -PVS( gs, ply+1, depth-1.0+ext, -alpha-1, -alpha,isID)
                if (val > alpha) && (val < beta)
                    val = -PVS( gs, ply+1, depth-1.0+ext, -beta, -alpha,isID)
                end
            else
                val = -PVS( gs, ply+1, depth-1.0+ext, -beta, -alpha,isID)
            end
            takeBack( gs.board, i, gs.moveBuf, teban)
            if gs.timedout
                return 0
            end
            if bestValue < val
                # both sides want to maximize from *their* perspective
                gs.pvmovesfound += 1
                gs.triangularArray[ply+1,ply+1] = gs.moveBuf[i]
		# save this move
                for j = (ply +1+1):gs.triangularLength[ply+1+1]
                    gs.triangularArray[ply+1,j] = gs.triangularArray[ply+1+1,j]
                    # and append the latest best PV from deeper plies
                end
                gs.triangularLength[ply+1] = gs.triangularLength[ply + 1+1]
                rememberPV(gs)
                
                tt_flag = TT_ALPHA
                tt_val = alpha
                tt_bestMove = gs.moveBuf[i]
                tt_save( depth, tt_val, tt_flag, tt_bestMove, gs)
            end
            bestValue=max(val,bestValue)
            alpha = max( alpha, val)
            if alpha >= beta
                if gs.board.nextMove == GOTE
                    gs.blackHeuristics[seeMoveFrom(gs.moveBuf[i])+1,seeMoveTo(gs.moveBuf[i])+1] += int(depth*depth)
                else
                    gs.whiteHeuristics[seeMoveFrom(gs.moveBuf[i])+1,seeMoveTo(gs.moveBuf[i])+1] += int(depth*depth)
                end
                    
                tt_flag = TT_BETA
                tt_val = beta
                tt_bestMove = gs.moveBuf[i]
                tt_save( depth, tt_val, tt_flag, gs.moveBuf[i], gs)
                return beta
            end
        end
    end

    if gs.pvmovesfound > 0
        if gs.board.nextMove == GOTE
            gs.blackHeuristics[seeMoveFrom(gs.triangularArray[ply+1,ply+1])+1,seeMoveTo(gs.triangularArray[ply+1,ply+1])+1] += int(depth*depth)
        else
            gs.whiteHeuristics[seeMoveFrom(gs.triangularArray[ply+1,ply+1])+1,seeMoveTo(gs.triangularArray[ply+1,ply+1])+1] += int(depth*depth)
        end
        tt_flag = TT_EXACT
        tt_save( depth, alpha, tt_flag, tt_bestMove, gs)
    end
    if movesfound == 0
	if in_check(teban, gs.board)
            #tt_save( depth, -Infinity+ply-1, tt_flag, tt_bestMove, gs)
            return -Infinity+ply-1
        end
    end
    bestValue
end

#end # @iprofile
